module Whatsapp
  # Extracts a transaction from free text or an audio transcript via OpenRouter, then
  # computes cents in Ruby (Money.to_cents) — the LLM emits amount_raw verbatim and never
  # multiplies (Review P1-2). One shared schema for text + transcript. See .plans/whats §4.5.
  class Extractor
    SYSTEM_PROMPT = <<~PT.freeze
      Você extrai UMA transação financeira de uma mensagem em português do Brasil.
      Regras:
      - Não invente. Se um campo não estiver na mensagem, retorne null com confiança 0.
      - Nunca fabrique valor, estabelecimento ou data.
      - Devolva o valor EXATAMENTE como dito (ex.: "13,23", "1.234,56"), sem converter para centavos.
      - instrument_phrase = as palavras exatas da conta/cartão citado (ex.: "cartão Nubank"), ou null.
      - occurred_on: data ISO só se explícita na mensagem; caso contrário null (será considerado hoje).
      - payment_method: debito, credito, pix, dinheiro, boleto ou desconhecido.
    PT

    SCHEMA = {
      name: "transaction_extraction",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[amount_raw currency merchant occurred_on payment_method
                         instrument_phrase field_confidence overall_confidence],
        "properties" => {
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
          "overall_confidence" => { "type" => "number" }
        }
      }
    }.freeze

    # Returns a Whatsapp::Extraction. `client` is injectable for tests.
    def self.from_text(user, text, modality: "text", client: nil)
      client ||= OpenRouterClient.new(task: :extraction)
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: text.to_s }
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
        raw:                parsed.merge("transcript" => text).compact
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
