# Pipeline for one uploaded document (D3): detect → parse → normalize → propose. Mirrors
# ProcessInboundWhatsappJob's orchestration (concurrency, retry/discard, terminal re-run guard,
# spend cap that fails WITHOUT calling AI). Phase 1 handles CSV/OFX deterministically (zero LLM);
# PDF short-circuits until Phase 2.
class ProcessDocumentImportJob < ApplicationJob
  queue_as :imports

  # 2 concurrent per user — documents are independent (unlike WhatsApp replies, which serialize
  # behind their open ask).
  limits_concurrency to: 2, key: ->(import_id) { DocumentImport.where(id: import_id).pick(:user_id) }

  retry_on OpenRouterClient::RateLimited, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(import_id)
    import = DocumentImport.find(import_id)
    return if import.terminal? # idempotent re-run guard

    import.update!(status: "processing")
    return fail!(import, "rate_limited") if over_daily_cap?(import)

    bytes  = import.file.download
    format = Imports::FormatDetector.call(bytes, filename: import.file.filename.to_s)
    return fail!(import, "unsupported_format") if format.nil?

    import.update!(source_format: format)
    import.update!(extraction: extract(format, bytes, import))
    Imports::ProposalBuilder.call(import)
  rescue Imports::PasswordProtected then fail!(import, "password_protected")
  rescue Imports::TooLarge          then fail!(import, "too_large")
  rescue Imports::ParseError        then fail!(import, "parse_failed")
  rescue OpenRouterClient::RateLimited, Net::OpenTimeout, Net::ReadTimeout
    raise # let retry_on resume; status stays "processing"
  rescue OpenRouterClient::Error then fail!(import, "llm_failed")
  end

  private

  def extract(format, bytes, import)
    case format
    when "csv" then Imports::CsvParser.call(bytes)
    when "ofx" then Imports::OfxParser.call(bytes)
    when "pdf" then extract_pdf(bytes, import)
    end
  end

  def extract_pdf(bytes, import)
    pdf = pre_extracted_pages(import) || Imports::PdfTextExtractor.call(bytes)
    # Scanned/garbled text layer → vision fallback (stubbed until Phase 4).
    raise Imports::ParseError, "scanned pdf — vision fallback lands in Phase 4" unless pdf["text_usable"]

    Imports::DocumentExtractor.call(pdf, import: import)
  end

  # The password-unlock flow (P1-3) decrypts in-request and stashes the extracted TEXT here, so the
  # job never re-opens the encrypted blob (the password never reaches the job args / DB).
  def pre_extracted_pages(import)
    extraction = import.extraction
    extraction if extraction.is_a?(Hash) && extraction["pages"].present? && extraction.key?("text_usable")
  end

  # Defense-in-depth behind the controller's cap: concurrent submits can race past it. Over the
  # cap → fail WITHOUT calling AI.
  def over_daily_cap?(import)
    import.user.document_imports.where(created_at: 24.hours.ago..).where.not(id: import.id)
          .count >= DocumentImport::MAX_PER_DAY
  end

  def fail!(import, error_code)
    import.update!(status: "failed", error_code: error_code)
  end
end
