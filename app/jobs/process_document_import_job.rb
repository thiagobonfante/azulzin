# Pipeline for one uploaded document (D3): detect → parse → normalize → propose. Mirrors
# ProcessInboundWhatsappJob's orchestration (concurrency, retry/discard, terminal re-run guard,
# spend cap that fails WITHOUT calling AI). Phase 1 handles CSV/OFX deterministically (zero LLM);
# PDF short-circuits until Phase 2.
class ProcessDocumentImportJob < ApplicationJob
  queue_as :imports

  # 2 concurrent per account — documents are independent (unlike WhatsApp replies, which serialize
  # behind their open ask). Keyed on account (D2): the daily cap is per family.
  limits_concurrency to: 2, key: ->(import_id) { DocumentImport.where(id: import_id).pick(:account_id) }

  # Every AI/transport failure retries (transient), then FAILS the import instead of dead-ending
  # — retry exhaustion without a handler left the import stuck at "processing" with a spinner
  # forever (the same silence ProcessInboundWhatsappJob's fail_and_tell killed). The generic
  # Error handler is declared BEFORE RateLimited so the more specific one (declared later,
  # matched first by rescue_from) keeps its polynomial backoff.
  retry_on OpenRouterClient::Error, wait: 5.seconds, attempts: 3 do |job, error|
    fail_import(job.arguments.first, "llm_failed", error)
  end
  retry_on OpenRouterClient::RateLimited, wait: :polynomially_longer, attempts: 3 do |job, error|
    fail_import(job.arguments.first, "llm_failed", error)
  end
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError,
           OpenSSL::SSL::SSLError, EOFError, wait: 5.seconds, attempts: 3 do |job, error|
    fail_import(job.arguments.first, "llm_failed", error)
  end
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  TRANSIENT = [ OpenRouterClient::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET,
                SocketError, OpenSSL::SSL::SSLError, EOFError ].freeze

  # Mark failed on retry exhaustion — a terminal status is the one thing that stops the spinner.
  def self.fail_import(import_id, error_code, error)
    import = DocumentImport.find_by(id: import_id)
    return if import.nil? || import.terminal?

    Rails.logger.error("Import #{import_id} failed: #{error.class}: #{error.message}")
    import.update!(status: "failed", error_code: error_code)
  end

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
  rescue *TRANSIENT
    raise # let retry_on resume; its exhaustion block fails the import
  rescue StandardError => e
    # Anything unexpected (storage, encoding, a parser bug) must never strand the import at
    # "processing" — fail it visibly and keep the exception for the error tracker.
    fail!(import, "parse_failed") if import
    raise e
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
    return Imports::DocumentExtractor.call(pdf, import: import) if pdf["text_usable"]

    # Scanned/garbled text layer → render pages to images and extract via the vision task (§5).
    images = Imports::PdfRasterizer.call(bytes)
    Imports::DocumentExtractor.call_vision(images)
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
    import.account.document_imports.where(created_at: 24.hours.ago..).where.not(id: import.id)
          .count >= DocumentImport::MAX_PER_DAY
  end

  def fail!(import, error_code)
    import.update!(status: "failed", error_code: error_code)
  end
end
