require "test_helper"

class Imports::PdfTextExtractorTest < ActiveSupport::TestCase
  test "extracts per-page text and flags a usable text layer" do
    pdf = Imports::PdfTextExtractor.call(file_fixture("imports/statement.pdf").binread)
    assert_equal 1, pdf["page_count"]
    assert_equal 1, pdf["pages"].size
    assert pdf["text_usable"]
    assert_includes pdf["pages"].first, "Santander"
  end

  test "flags an empty text layer as not usable (vision fallback signal)" do
    pdf = Imports::PdfTextExtractor.call(file_fixture("imports/no_text.pdf").binread)
    assert_not pdf["text_usable"]
  end

  test "raises TooLarge over the page cap before extracting text" do
    assert_raises(Imports::TooLarge) do
      Imports::PdfTextExtractor.call(file_fixture("imports/pages26.pdf").binread)
    end
  end

  test "maps an encrypted PDF to PasswordProtected" do
    PDF::Reader.stub(:new, ->(*_a, **_k) { raise PDF::Reader::EncryptedPDFError }) do
      assert_raises(Imports::PasswordProtected) { Imports::PdfTextExtractor.call("whatever") }
    end
  end

  test "maps a malformed PDF to ParseError" do
    assert_raises(Imports::ParseError) { Imports::PdfTextExtractor.call("%PDF-1.4 not really a pdf") }
  end

  test "passes the password through to the reader (used in memory only)" do
    seen = nil
    PDF::Reader.stub(:new, ->(_io, password: nil) { seen = password; raise PDF::Reader::EncryptedPDFError }) do
      assert_raises(Imports::PasswordProtected) { Imports::PdfTextExtractor.call("x", password: "cpf1234") }
    end
    assert_equal "cpf1234", seen
  end
end
