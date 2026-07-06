require "pdf-reader"
require "stringio"

# pdf-reader text layer → pages of text (§7.3). Pure Ruby, in-process (no shell-out). PDF rows
# come from the LLM extraction stage (DocumentExtractor); this only pulls the raw page text and
# flags a scanned/garbled layer for the vision fallback. `password` (P1-3) is used in-memory only
# and never persisted — the controller decrypts in-request and hands the job the extracted text.
module Imports
  module PdfTextExtractor
    module_function

    USABLE_ALNUM_MIN = 200 # a page is "usable" with ≥ this many alphanumerics; doc usable if ≥ half its pages are

    def call(bytes, password: nil)
      reader = PDF::Reader.new(StringIO.new(bytes.to_s), password: password.to_s)
      raise TooLarge, "pdf over #{DocumentImport::PDF_PAGE_CAP}-page cap" if reader.page_count > DocumentImport::PDF_PAGE_CAP

      pages = reader.pages.map { |page| page_text(page) }
      { "format" => "pdf", "pages" => pages, "page_count" => pages.size, "text_usable" => usable?(pages) }
    rescue PDF::Reader::EncryptedPDFError
      raise PasswordProtected
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      raise ParseError
    end

    # One broken page never kills the doc — it yields "".
    def page_text(page)
      page.text.to_s
    rescue StandardError
      ""
    end

    def usable?(pages)
      return false if pages.empty?

      pages.count { |text| text.count("a-zA-Z0-9") >= USABLE_ALNUM_MIN } >= (pages.size / 2.0)
    end
  end
end
