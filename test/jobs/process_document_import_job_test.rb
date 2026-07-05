require "test_helper"
require_relative "../test_helpers/import_extraction_fixtures"

class ProcessDocumentImportJobTest < ActiveJob::TestCase
  include ImportExtractionFixtures

  setup { @user = users(:confirmed) }

  test "PDF runs text extraction + LLM to extracted with a credit_card proposal" do
    import = upload_bytes(file_fixture("imports/statement.pdf").binread, "fatura.pdf", "application/pdf")
    stub_classifier do
      Imports::DocumentExtractor.stub(:call, ->(_pdf, **_k) { fatura_extraction }) do
        ProcessDocumentImportJob.perform_now(import.id)
      end
    end
    import.reload
    assert_equal "extracted", import.status
    assert_equal "pdf", import.source_format
    assert_equal "card_bill", import.kind
    assert import.proposals.any? { it["kind"] == "credit_card" }
  end

  test "an encrypted PDF fails password_protected" do
    import = upload_bytes(file_fixture("imports/statement.pdf").binread, "enc.pdf", "application/pdf")
    Imports::PdfTextExtractor.stub(:call, ->(*_a, **_k) { raise Imports::PasswordProtected }) do
      ProcessDocumentImportJob.perform_now(import.id)
    end
    assert_equal "failed", import.reload.status
    assert_equal "password_protected", import.error_code
  end

  test "a scanned PDF (no text layer) routes to the vision fallback and caps confidence" do
    import = upload_bytes(file_fixture("imports/no_text.pdf").binread, "scan.pdf", "application/pdf")
    vision = fatura_extraction.merge("vision" => true)
    stub_classifier do
      Imports::PdfRasterizer.stub(:call, ->(*_a, **_k) { [ "png-bytes" ] }) do
        Imports::DocumentExtractor.stub(:call_vision, ->(*_a, **_k) { vision }) do
          ProcessDocumentImportJob.perform_now(import.id)
        end
      end
    end
    import.reload
    assert_equal "extracted", import.status
    assert import.proposals.any?
    assert import.proposals.all? { it["confidence"] <= Imports::Confidence::VISION_CAP }
  end

  test "a PDF over the page cap fails too_large without an LLM call" do
    import = upload_bytes(file_fixture("imports/pages26.pdf").binread, "big.pdf", "application/pdf")
    called = false
    Imports::DocumentExtractor.stub(:call, ->(*_a, **_k) { called = true; {} }) do
      ProcessDocumentImportJob.perform_now(import.id)
    end
    assert_equal "failed", import.reload.status
    assert_equal "too_large", import.error_code
    assert_not called
  end

  test "OFX runs the deterministic pipeline to extracted with a bank_account proposal" do
    import = upload("nubank.ofx", "application/x-ofx")
    stub_classifier { ProcessDocumentImportJob.perform_now(import.id) }
    import.reload

    assert_equal "extracted", import.status
    assert_equal "ofx", import.source_format
    assert_equal "0260", import.fingerprint["bank_code"]
    assert_equal 357625, import.fingerprint["ledger_balance_cents"]
    assert import.proposals.any? { it["kind"] == "bank_account" }
    assert_equal "260", import.institution.code
  end

  test "CSV extracts but proposes no bank_account (no account identity)" do
    import = upload("sample.csv", "text/csv")
    stub_classifier { ProcessDocumentImportJob.perform_now(import.id) }
    import.reload
    assert_equal "extracted", import.status
    assert_equal "csv", import.source_format
    assert_empty import.proposals
  end

  test "terminal imports are not reprocessed (idempotent, no duplicate proposals)" do
    import = upload("nubank.ofx", "application/x-ofx")
    stub_classifier do
      ProcessDocumentImportJob.perform_now(import.id)
      proposals = import.reload.proposals
      ProcessDocumentImportJob.perform_now(import.id)
      assert_equal proposals, import.reload.proposals
    end
  end

  test "a parse failure marks failed/parse_failed" do
    import = upload_bytes("Foo,Bar\n1,2\n", "junk.csv", "text/csv")
    ProcessDocumentImportJob.perform_now(import.id)
    assert_equal "failed", import.reload.status
    assert_equal "parse_failed", import.error_code
  end

  test "over the daily cap fails without processing" do
    10.times { @user.document_imports.new(checksum: SecureRandom.hex).save!(validate: false) }
    import = upload("nubank.ofx", "application/x-ofx")
    ProcessDocumentImportJob.perform_now(import.id)
    assert_equal "failed", import.reload.status
    assert_equal "rate_limited", import.error_code
    assert_empty import.proposals
  end

  private

  def upload(fixture, type)
    build_import { it.file.attach(io: File.open(file_fixture("imports/#{fixture}")), filename: fixture, content_type: type) }
  end

  def upload_bytes(bytes, name, type)
    build_import { it.file.attach(io: StringIO.new(bytes), filename: name, content_type: type) }
  end

  def build_import
    import = @user.document_imports.new(checksum: SecureRandom.hex)
    yield import
    import.save!
    import
  end
end
