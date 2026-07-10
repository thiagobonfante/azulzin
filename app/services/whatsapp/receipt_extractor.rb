module Whatsapp
  # Extracts a transaction from a receipt / nota fiscal / card-slip / Pix-transfer PHOTO via
  # an OpenRouter vision model. Trimmed schema (no line items — Review P2-2). Ruby computes
  # cents from the printed total (the LLM never multiplies). Deterministic cross-checks cap
  # confidence so a shaky read parks instead of posting silently. See .plans/whats §4.4.
  class ReceiptExtractor
    SYSTEM_PROMPT = <<~PT.freeze
      Você lê a evidência de um pagamento brasileiro na imagem — comprovante de compra (cupom
      fiscal, NFC-e, comprovante de cartão/maquininha), comprovante de transferência/Pix de
      banco/app, OU um print/screenshot que confirme uma compra ou pagamento (notificação do
      banco, tela do app, e-mail de confirmação) — e extrai os dados do pagamento.
      Regras:
      - total_raw = o VALOR TOTAL PAGO, exatamente como impresso (ex.: "1.234,56"). Nunca o
        subtotal nem um item isolado. Não converta para centavos.
      - payment_method: debito, credito, pix, dinheiro, vale, boleto, outro ou desconhecido
        (leia "DÉBITO"/"CRÉDITO"/"PIX"/"DINHEIRO" impresso; desconhecido se ambíguo).
      - Comprovante de transferência/Pix: document_type = "transferencia"; merchant_name =
        o nome do DESTINO (favorecido/recebedor); origin_phrase = instituição + nome de
        quem PAGOU (a ORIGEM, ex.: "Nu Pagamentos Franciane"); payment_method conforme o
        tipo impresso (Pix → pix).
      - origin_phrase = null em comprovantes de compra.
      - purchase_date em ISO (YYYY-MM-DD) só se estiver no comprovante; senão null.
      - is_receipt = false se a imagem não mostrar um pagamento REALIZADO. Um boleto ainda
        não pago, um orçamento, um carrinho ou uma tela de produto NÃO são pagamentos.
      - category: um palpite de categoria do gasto, se der (será resolvido no app).
      - Preencha field_confidence e overall_confidence com honestidade. Não invente.
    PT

    SCHEMA = {
      name: "brazilian_receipt_extraction",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[is_receipt document_type merchant_name merchant_cnpj purchase_date
                         currency total_raw payment_method origin_phrase field_confidence
                         overall_confidence notes category],
        "properties" => {
          "is_receipt"    => { "type" => "boolean" },
          "document_type" => { "type" => "string", "enum" => %w[nfce nfe cupom_fiscal card_slip transferencia other] },
          "merchant_name" => { "type" => %w[string null] },
          "merchant_cnpj" => { "type" => %w[string null] },
          "purchase_date" => { "type" => %w[string null] },
          "currency"      => { "type" => "string", "enum" => %w[BRL] },
          "total_raw"     => { "type" => %w[string null] },
          "payment_method" => { "type" => "string",
                                "enum" => %w[debito credito pix dinheiro vale boleto outro desconhecido] },
          "origin_phrase" => { "type" => %w[string null] },
          "field_confidence" => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[merchant total date payment_method],
            "properties" => %w[merchant total date payment_method].index_with { { "type" => "number" } }
          },
          "overall_confidence" => { "type" => "number" },
          "notes" => { "type" => %w[string null] },
          "category" => { "type" => %w[string null] }
        }
      }
    }.freeze

    def self.from_message(msg, client: nil)
      url = data_url(msg.media)   # raises Imports::ParseError on an unreadable PDF
      client ||= OpenRouterClient.new(task: :vision)
      caption = msg.body
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: [
          { type: "text", text: [ "Extraia os dados deste comprovante.",
                                  ("Legenda enviada pelo usuário: #{caption}" if caption.present?),
                                  Categories.closed_set_line(msg.account || msg.user&.account) ].compact.join("\n\n") },
          { type: "image_url", image_url: { url: url } }
        ] }
      ]
      build(client.chat(messages: messages, schema: SCHEMA).parsed || {}, caption)
    rescue Imports::ParseError
      # Corrupt PDF / no Ghostscript: nothing readable — same outcome as a non-receipt
      # image (caption fallback or the not_receipt reply), never a dead job.
      not_receipt
    end

    def self.build(parsed, caption = nil)
      return not_receipt unless parsed["is_receipt"]
      total_raw = parsed["total_raw"]
      Extraction.new(
        amount_raw:         total_raw,
        amount_cents:       (Money.to_cents(total_raw) if total_raw.present?),
        currency:           "BRL",
        merchant:           parsed["merchant_name"].presence,
        occurred_on:        Whatsapp::Extractor.parse_date(parsed["purchase_date"]),
        payment_method:     payment_method(parsed, caption),
        # A transfer receipt's printed ORIGIN wins; purchase receipts print none, so the
        # caption ("Cartão santander") is the deterministic instrument hint.
        instrument_phrase:  parsed["origin_phrase"].presence || caption.presence,
        field_confidence:   { "amount" => parsed.dig("field_confidence", "total") },
        overall_confidence: effective_confidence(parsed, total_raw),
        modality:           "image",
        source:             "whatsapp_receipt",
        raw:                parsed,
        category:           parsed["category"].presence
      )
    end

    # The PRINTED method always wins; the caption only fills "desconhecido", and only when it
    # names crédito XOR débito (decision 9: a caption never hard-overrides a printed DÉBITO).
    def self.payment_method(parsed, caption)
      pm = parsed["payment_method"].presence || "desconhecido"
      return pm unless pm == "desconhecido" && caption.present?
      credit = caption.match?(Whatsapp::Matcher::CREDIT_RE)
      debit  = caption.match?(Whatsapp::Matcher::DEBIT_RE)
      return "credito" if credit && !debit
      return "debito"  if debit && !credit
      pm
    end

    # Deterministic caps: a missing/unparseable total, or a future/implausible date, must not
    # post silently — cap below the floor so it parks/asks.
    def self.effective_confidence(parsed, total_raw)
      conf = parsed["overall_confidence"].to_f
      cents = (Money.to_cents(total_raw) if total_raw.present?)
      conf = [ conf, 0.50 ].min if cents.nil? || cents <= 0
      date = parsed["purchase_date"]
      conf = [ conf, 0.60 ].min if date.present? && Whatsapp::Extractor.parse_date(date).nil?
      conf
    end

    def self.not_receipt
      Extraction.new(amount_raw: nil, amount_cents: nil, currency: "BRL", payment_method: "desconhecido",
                     field_confidence: {}, overall_confidence: 0.0, modality: "image",
                     source: "whatsapp_receipt", raw: { "is_receipt" => false })
    end

    # Vision models take images, not PDFs — a WhatsApp document receipt (Pix comprovante
    # exported as PDF) is rasterized to PNG first, reusing the import pipeline's renderer.
    # Page 1 only: comprovantes are single-page.
    def self.data_url(media)
      if media.content_type.to_s.start_with?("application/pdf")
        png = Imports::PdfRasterizer.call(media.download, max_pages: 1).first
        "data:image/png;base64,#{Base64.strict_encode64(png)}"
      else
        "data:#{media.content_type};base64,#{Base64.strict_encode64(media.download)}"
      end
    end
  end
end
