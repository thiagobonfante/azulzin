require "base64"

# PDF text → structured extraction (D4, §3). Mirrors Whatsapp::Extractor's law: the LLM emits
# VERBATIM *_raw strings and NEVER computes cents, picks IDs, or infers years — Ruby does all of
# that in `build` (Money.to_cents, period-anchored year inference, running-Saldo balance anchor).
# CSV/OFX never reach this class. Single call for short docs; page-batched (§4) for long ones so
# an 8k output cap never truncates mid-row. `client:` is injectable for tests (no VCR — D10).
module Imports
  module DocumentExtractor
    module_function

    SINGLE_CALL_MAX_PAGES = 4
    PAGES_PER_BATCH = 2

    SYSTEM_PROMPT = <<~PT.freeze
      Você lê o TEXTO extraído de um documento financeiro brasileiro (extrato de conta corrente
      ou fatura de cartão de crédito) e o converte em dados estruturados.
      Não invente. Se um dado não estiver no texto, retorne null com confiança baixa.
      Regras:
      - doc_kind: bank_statement (extrato de conta), card_bill (fatura de cartão) ou unknown.
      - institution_name / bank_code: nome do banco e código COMPE SÓ SE IMPRESSOS no texto
        (ex.: "033", "260"). Nunca deduza o código pelo nome.
      - agency / account_number / holder_name: exatamente como impressos (mantenha zeros à
        esquerda e dígito verificador, ex.: "01003172-6").
      - closing_balance_raw: em extratos, o SALDO da linha de movimentação MAIS RECENTE do
        período (saldo final). NÃO use um saldo de resumo com data posterior ao período. null
        em faturas.
      - Valores monetários SEMPRE VERBATIM em *_raw (ex.: "48.025,80", "-11.90", "9,99").
        Nunca converta para centavos, nunca some, nunca calcule.
      - Datas SEMPRE VERBATIM em *_raw, como impressas ("22/06", "10/07/2026", "15/11"). NÃO
        complete o ano quando ele não estiver impresso — o app deduz o ano pelo período.
      - direction: debit para saídas/compras, credit para entradas/estornos/pagamentos.
      - Cada linha da tabela vira UMA entrada em rows, na ordem do documento. Descrições em
        várias linhas físicas são UMA entrada (junte o texto).
      - Compras internacionais ocupam 3 linhas (valor + "COTAÇÃO DOLAR" + "IOF"): devolva UMA
        entrada com fx preenchido (usd_raw, cotacao_raw, iof_raw) — não crie linhas separadas.
      - "Parcela NN/MM" ou "Parc NN/MM" → installment {current: NN, total: MM}; senão null.
      - Faturas com vários cartões (seções por plástico "NOME 4258 •••• 8431"): preencha
        section_last4 de cada linha; liste cada plástico em card.sections (is_virtual = true
        quando o nome começa com "@").
      - Ignore rodapés, propaganda, texto legal e linhas de saldo/resumo que não sejam
        movimentações.
      - overall_confidence de 0 a 1: quão fiel a extração é ao texto.
    PT

    SCHEMA = {
      name: "import_document_extraction",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[doc_kind institution_name bank_code agency account_number holder_name
                         period_start_raw period_end_raw closing_balance_raw card rows overall_confidence],
        "properties" => {
          "doc_kind"         => { "type" => "string", "enum" => %w[bank_statement card_bill unknown] },
          "institution_name" => { "type" => %w[string null] },
          "bank_code"        => { "type" => %w[string null] },
          "agency"           => { "type" => %w[string null] },
          "account_number"   => { "type" => %w[string null] },
          "holder_name"      => { "type" => %w[string null] },
          "period_start_raw" => { "type" => %w[string null] },
          "period_end_raw"   => { "type" => %w[string null] },
          "closing_balance_raw" => { "type" => %w[string null] },
          "card" => {
            "type" => %w[object null], "additionalProperties" => false,
            "required" => %w[sections limit_raw total_raw due_date_raw melhor_dia_raw],
            "properties" => {
              "sections" => { "type" => "array", "items" => {
                "type" => "object", "additionalProperties" => false,
                "required" => %w[last4 holder is_virtual],
                "properties" => {
                  "last4"      => { "type" => "string" },
                  "holder"     => { "type" => %w[string null] },
                  "is_virtual" => { "type" => "boolean" } } } },
              "limit_raw"      => { "type" => %w[string null] },
              "total_raw"      => { "type" => %w[string null] },
              "due_date_raw"   => { "type" => %w[string null] },
              "melhor_dia_raw" => { "type" => %w[string null] } } },
          "rows" => { "type" => "array", "items" => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[date_raw description amount_raw direction installment fx section_last4],
            "properties" => {
              "date_raw"    => { "type" => %w[string null] },
              "description" => { "type" => "string" },
              "amount_raw"  => { "type" => %w[string null] },
              "direction"   => { "type" => "string", "enum" => %w[debit credit] },
              "installment" => { "type" => %w[object null], "additionalProperties" => false,
                                 "required" => %w[current total],
                                 "properties" => { "current" => { "type" => "integer" },
                                                   "total"   => { "type" => "integer" } } },
              "fx" => { "type" => %w[object null], "additionalProperties" => false,
                        "required" => %w[usd_raw cotacao_raw iof_raw],
                        "properties" => %w[usd_raw cotacao_raw iof_raw].index_with { { "type" => %w[string null] } } },
              "section_last4" => { "type" => %w[string null] } } } },
          "overall_confidence" => { "type" => "number" }
        }
      }
    }.freeze

    def call(pdf, import: nil, client: nil)
      client ||= OpenRouterClient.new(task: :import_extraction)
      pages   = Array(pdf["pages"])
      parsed  = pages.size <= SINGLE_CALL_MAX_PAGES ? extract_single(pages, client) : extract_batched(pages, client)
      raise ParseError, "empty llm extraction" if parsed.blank?

      build(parsed)
    end

    # Vision fallback (§5): scanned pages rendered to PNG → the same SCHEMA via the multimodal
    # import_vision task. Flags the extraction `vision: true` so every proposal gets the OCR cap.
    # Long scans are page-batched like the text path (§4) — all pages in one call blew the output
    # cap and truncated rows silently.
    def call_vision(images, client: nil)
      images = Array(images)
      raise ParseError, "no pages to rasterize" if images.empty?

      client ||= OpenRouterClient.new(task: :import_vision)
      parsed  = images.size <= SINGLE_CALL_MAX_PAGES ? chat_vision(client, images) : vision_batched(images, client)
      raise ParseError, "empty vision extraction" if parsed.blank?

      build(parsed).merge("vision" => true)
    end

    def vision_batched(images, client)
      meta = chat_vision(client, images.first(1), extra: META_ONLY)
      rows = images.each_slice(PAGES_PER_BATCH).flat_map do |batch|
        Array(chat_vision(client, batch, extra: ROWS_ONLY)["rows"])
      end
      meta.merge("rows" => rows)
    end

    def chat_vision(client, images, extra: nil)
      text = [ extra, "Extraia os dados deste documento financeiro." ].compact.join("\n\n")
      content = [ { "type" => "text", "text" => text } ]
      images.each { |png| content << { "type" => "image_url", "image_url" => { "url" => data_url(png) } } }
      messages = [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: content } ]
      parsed_or_raise(client.chat(messages: messages, schema: SCHEMA))
    end

    def data_url(png)
      "data:image/png;base64,#{Base64.strict_encode64(png)}"
    end

    def extract_single(pages, client)
      chat(client, pages.join("\n\n"))
    end

    META_ONLY = "Extraia apenas doc_kind, identidade, período e card; rows deve ser [].".freeze
    ROWS_ONLY = "Extraia apenas rows (metadados null).".freeze

    # Metadata call (page 1) + row calls (2-page batches), merged in Ruby (§4).
    def extract_batched(pages, client)
      meta = chat(client, pages.first, extra: META_ONLY)
      rows = pages.each_slice(PAGES_PER_BATCH).flat_map do |batch|
        Array(chat(client, batch.join("\n\n"), extra: ROWS_ONLY)["rows"])
      end
      meta.merge("rows" => rows)
    end

    def chat(client, text, extra: nil)
      content = extra ? "#{extra}\n\n#{text}" : text
      messages = [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: content } ]
      parsed_or_raise(client.chat(messages: messages, schema: SCHEMA))
    end

    # A nil parse means the completion wasn't valid JSON (output-cap truncation is the usual
    # culprit). Silently treating it as {} dropped whole page-batches of rows — fail loudly so
    # the job retries/reports instead.
    def parsed_or_raise(result)
      result.parsed or raise ParseError, "unparseable llm extraction"
    end

    # ── Ruby post-processing (all money/dates here, never the LLM) ────────────
    def build(parsed)
      period_start = full_date(parsed["period_start_raw"])
      period_end   = full_date(parsed["period_end_raw"]) || period_start
      {
        "format"   => "pdf",
        "doc_kind" => parsed["doc_kind"].presence || "unknown",
        "meta" => {
          "institution_name" => parsed["institution_name"],
          "bank_code"        => parsed["bank_code"],
          "holder_name"      => parsed["holder_name"],
          "acct" => {
            "bank_id"   => parsed["bank_code"],
            "branch_id" => parsed["agency"],
            "acct_id"   => parsed["account_number"]
          }.compact,
          "period_start"          => period_start&.iso8601,
          "period_end"            => period_end&.iso8601,
          "closing_balance_cents" => Money.to_cents(parsed["closing_balance_raw"]),
          "card"                  => build_card(parsed["card"], period_end)
        }.compact,
        "rows"       => Array(parsed["rows"]).map { |row| build_row(row, period_end) },
        "confidence" => parsed["overall_confidence"] || 0.7
      }
    end

    def build_card(card, period_end)
      return nil if card.blank?

      due = infer_due_date(card["due_date_raw"], period_end)
      {
        "last4"               => titular_last4(Array(card["sections"])),
        "sections"            => Array(card["sections"]),
        "credit_limit_cents"  => Money.to_cents(card["limit_raw"]),
        "current_bill_cents"  => Money.to_cents(card["total_raw"]),
        "due_date"            => due&.iso8601,
        "bill_due_day"        => due&.day,
        "closing_offset_days" => closing_offset(due, period_end)
      }
    end

    def build_row(row, period_end)
      {
        "date"          => infer_txn_date(row["date_raw"], period_end)&.iso8601,
        "description"   => row["description"].to_s.gsub(/\s+/, " ").strip,
        "amount_cents"  => (Money.to_cents(row["amount_raw"]) || 0).abs,
        "direction"     => (row["direction"] == "credit" ? "in" : "out"),
        "external_id"   => nil,
        "installment"   => row["installment"],
        "fx"            => row["fx"],
        "section_last4" => row["section_last4"],
        "raw"           => row,
        "signals"       => []
      }
    end

    def titular_last4(sections)
      physical = sections.find { |s| s["is_virtual"] == false }
      (physical || sections.first)&.dig("last4")
    end

    def closing_offset(due, period_end)
      return 7 unless due && period_end

      offset = (due - period_end).to_i
      offset.between?(1, 28) ? offset : 7
    end

    # Faturas print two-digit years ("18/06/26") and %Y accepts them as year 0026 — a plan
    # anchored 2000 years in the past reads as fully elapsed everywhere. Century-guard here.
    def full_date(raw)
      return nil if raw.blank?

      date = Date.strptime(raw.to_s.strip, "%d/%m/%Y")
      date.year < 100 ? date.next_year(2000) : date
    rescue ArgumentError
      nil
    end

    # Due dates fall AT/AFTER the period end → infer forward.
    def infer_due_date(raw, period_end)
      full = full_date(raw)
      return full if full

      parts = ddmm(raw)
      return nil unless parts && period_end

      day, month = parts
      candidate = safe_date(period_end.year, month, day)
      return nil unless candidate

      candidate < period_end ? safe_date(period_end.year + 1, month, day) : candidate
    end

    # Transaction/Compra dates fall AT/BEFORE the period end → infer backward.
    def infer_txn_date(raw, period_end)
      full = full_date(raw)
      return full if full

      parts = ddmm(raw)
      return nil unless parts

      day, month = parts
      # No printed period → anchor on today: onboarding rows are always in the past, and a
      # Dec-31 anchor put January-processed December docs a year in the future.
      ref = period_end || Date.current
      candidate = safe_date(ref.year, month, day)
      return nil unless candidate

      candidate > ref ? safe_date(ref.year - 1, month, day) : candidate
    end

    def ddmm(raw)
      m = raw.to_s.match(%r{(\d{1,2})/(\d{1,2})}) or return nil

      [ m[1].to_i, m[2].to_i ]
    end

    def safe_date(year, month, day)
      Date.new(year, month, day)
    rescue ArgumentError
      nil
    end
  end
end
