require "test_helper"

class ProcessDocumentImportJobTest < ActiveJob::TestCase
  setup { @user = users(:confirmed) }

  test "OFX runs the deterministic pipeline to extracted with a bank_account proposal" do
    import = upload("nubank.ofx", "application/x-ofx")
    ProcessDocumentImportJob.perform_now(import.id)
    import.reload

    assert_equal "extracted", import.status
    assert_equal "ofx", import.source_format
    assert_equal "0260", import.fingerprint["bank_code"]
    assert_equal 357625, import.fingerprint["ledger_balance_cents"]
    assert_equal 1, import.proposals.size
    assert_equal "bank_account", import.proposals.first["kind"]
    assert_equal "260", import.institution.code
  end

  test "CSV extracts but proposes no bank_account (no account identity)" do
    import = upload("sample.csv", "text/csv")
    ProcessDocumentImportJob.perform_now(import.id)
    import.reload
    assert_equal "extracted", import.status
    assert_equal "csv", import.source_format
    assert_empty import.proposals
  end

  test "PDF short-circuits to failed/unsupported_format in Phase 1" do
    import = upload_bytes("%PDF-1.7\nfake pdf body", "fatura.pdf", "application/pdf")
    ProcessDocumentImportJob.perform_now(import.id)
    assert_equal "failed", import.reload.status
    assert_equal "unsupported_format", import.error_code
  end

  test "terminal imports are not reprocessed (idempotent, no duplicate proposals)" do
    import = upload("nubank.ofx", "application/x-ofx")
    ProcessDocumentImportJob.perform_now(import.id)
    proposals = import.reload.proposals
    ProcessDocumentImportJob.perform_now(import.id)
    assert_equal proposals, import.reload.proposals
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
