module Whatsapp
  # Extracts a transaction from free text or an audio transcript via OpenRouter, then
  # computes cents in Ruby (Money.to_cents) — the LLM emits amount_raw verbatim and never
  # multiplies (Review P1-2). One shared schema for text + transcript. See .plans/whats §4.5.
  class Extractor
    SYSTEM_PROMPT = <<~PT.freeze
      Você classifica a intenção e extrai os campos de UMA mensagem financeira em português do Brasil.
      Não invente. Se um campo não estiver na mensagem, retorne null com confiança 0.
      intents:
      - expense: gasto/compra à vista ("mercado 84,90 no débito", "gastei 32 no cartão nubank").
      - income: recebimento ("recebi o salário, 4500", "caiu 1200 de pensão").
      - transfer: transferência entre contas, incluindo "guardar na caixinha/poupança/reserva".
      - installment_purchase: compra parcelada ("comprei um celular, 5000 em 10x", "6x de 300").
      - pay_commitment: pagamento de compromisso/parcela/conta fixa ("paguei a parcela do carro", "pensão paga").
      - move_bill: mover uma compra para outra fatura ("joga pra próxima fatura").
      - edit_last: corrigir o último lançamento ("na verdade foi 54,90", "era no crédito",
        "muda a categoria pra mercado").
      - undo_last: desfazer/cancelar o último ("apaga o último", "cancela isso").
      - query: consulta de saldo/fatura/mês ("quanto tenho na nubank?", "como tá o mês?").
      - other: qualquer outra coisa.
      Regras:
      - intent_confidence de 0 a 1 (quão certa é a classificação).
      - Devolva valores EXATAMENTE como ditos (ex.: "13,23", "1.234,56"), sem converter para centavos.
        Um número sem centavos é um valor válido em reais ("gastei 32" → amount_raw "32").
      - instrument_phrase = conta/cartão citado (expense/income) ou a ORIGEM da transferência.
      - to_instrument_phrase = DESTINO da transferência ("pra caixinha", "pra poupança").
      - installments_count = número de parcelas ("em 10x" → 10). installment_total_raw / installment_parcel_raw conforme dito.
      - commitment_phrase = o compromisso citado ("o carro", "a pensão", "netflix").
      - occurred_on: data ISO só se explícita; caso contrário null.
      - payment_method: debito, credito, pix, dinheiro, boleto ou desconhecido.
      - category: um palpite de categoria do gasto, se der (será resolvido no app). Em edit_last
        de categoria, é a categoria pedida.
      - edit_field_hint: qual campo o edit_last corrige (amount, merchant, instrument, date, category).
    PT

    SCHEMA = {
      name: "transaction_extraction",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[intent intent_confidence amount_raw currency merchant occurred_on payment_method
                         instrument_phrase field_confidence overall_confidence
                         to_instrument_phrase installments_count installment_total_raw
                         installment_parcel_raw commitment_phrase target_bill_raw
                         edit_field_hint query_kind category],
        "properties" => {
          "intent"            => { "type" => "string",
                                   "enum" => %w[expense income transfer installment_purchase pay_commitment
                                                move_bill edit_last undo_last query other] },
          "intent_confidence" => { "type" => "number" },
          "amount_raw"        => { "type" => %w[string null] },
          "currency"          => { "type" => "string", "enum" => %w[BRL] },
          "merchant"          => { "type" => %w[string null] },
          "occurred_on"       => { "type" => %w[string null] },
          "payment_method"    => { "type" => "string",
                                   "enum" => %w[debito credito pix dinheiro boleto desconhecido] },
          "instrument_phrase" => { "type" => %w[string null] },
          "field_confidence"  => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[amount merchant date payment_method instrument],
            "properties" => %w[amount merchant date payment_method instrument]
              .index_with { { "type" => "number" } }
          },
          "overall_confidence"     => { "type" => "number" },
          "to_instrument_phrase"   => { "type" => %w[string null] },
          "installments_count"     => { "type" => %w[integer null] },
          "installment_total_raw"  => { "type" => %w[string null] },
          "installment_parcel_raw" => { "type" => %w[string null] },
          "commitment_phrase"      => { "type" => %w[string null] },
          "target_bill_raw"        => { "type" => %w[string null] },
          "edit_field_hint"        => { "type" => %w[string null], "enum" => [ "amount", "merchant", "instrument", "date", "category", nil ] },
          "query_kind"             => { "type" => %w[string null], "enum" => [ "account_balance", "card_bill", "month_summary", "savings_total", nil ] },
          "category"               => { "type" => %w[string null] }
        }
      }
    }.freeze

    # Returns a Whatsapp::Extraction. `client` is injectable for tests.
    def self.from_text(user, text, modality: "text", client: nil)
      client ||= OpenRouterClient.new(task: :extraction)
      # Closed-set category line in the USER message (per-account data never goes in the
      # frozen shared system prompt); the answer is still a string, resolved in Ruby.
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: [ text.to_s, Categories.closed_set_line(user&.account) ].compact.join("\n\n") }
      ]
      parsed = client.chat(messages: messages, schema: SCHEMA).parsed || {}
      build(parsed, modality:, source: source_for(modality), text: text)
    end

    def self.build(parsed, modality:, source:, text: nil)
      amount_raw = parsed["amount_raw"]
      Extraction.new(
        amount_raw:         amount_raw,
        amount_cents:       (Money.to_cents(amount_raw) if amount_raw.present?),
        currency:           parsed["currency"] || "BRL",
        merchant:           parsed["merchant"].presence,
        occurred_on:        parse_date(parsed["occurred_on"]),
        payment_method:     parsed["payment_method"].presence || "desconhecido",
        instrument_phrase:  parsed["instrument_phrase"].presence,
        field_confidence:   parsed["field_confidence"] || {},
        overall_confidence: parsed["overall_confidence"] || 0.0,
        modality:           modality,
        source:             source,
        raw:                parsed.merge("transcript" => text).compact,
        intent:                 parsed["intent"].presence || "expense",
        intent_confidence:      parsed["intent_confidence"] || 0.0,
        to_instrument_phrase:   parsed["to_instrument_phrase"].presence,
        installments_count:     parsed["installments_count"],
        installment_total_raw:  parsed["installment_total_raw"].presence,
        installment_parcel_raw: parsed["installment_parcel_raw"].presence,
        commitment_phrase:      parsed["commitment_phrase"].presence,
        target_bill_raw:        parsed["target_bill_raw"].presence,
        edit_field_hint:        parsed["edit_field_hint"].presence,
        query_kind:             parsed["query_kind"].presence,
        category:               parsed["category"].presence
      )
    end

    # Explicit ISO date only; reject blanks and future dates (computed in São Paulo).
    def self.parse_date(value)
      return nil if value.blank?
      d = Date.iso8601(value.to_s) rescue nil
      return nil if d.nil? || d > Time.current.to_date
      d
    end

    def self.source_for(modality)
      case modality.to_s
      when "audio" then "whatsapp_audio"
      when "image" then "whatsapp_receipt"
      else "whatsapp_text"
      end
    end
  end
end
