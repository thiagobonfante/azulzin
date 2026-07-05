require "test_helper"
require_relative "../test_helpers/import_extraction_fixtures"

class DocumentImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ImportExtractionFixtures

  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678") # not onboarded (onboarded_at nil)
    sign_in_as(@user)
  end

  test "upload creates a DocumentImport with checksum, blob and status uploaded" do
    assert_difference -> { @user.document_imports.count }, 1 do
      post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    end
    di = @user.document_imports.order(:created_at).last
    assert_equal "uploaded", di.status
    assert di.file.attached?
    assert_equal Digest::SHA256.file(file_fixture("imports/sample.csv").to_s).hexdigest, di.checksum
    assert_redirected_to onboarding_step_url("accounts")
  end

  test "re-uploading the same bytes is rejected as a duplicate" do
    post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    assert_no_difference -> { @user.document_imports.count } do
      post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    end
    assert_equal I18n.t("document_imports.errors.duplicate_file"), flash[:alert]
  end

  test "a different user can upload the same bytes (per-user dedupe)" do
    post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    other = User.create!(email_address: "other@example.com", password: "password123")
    sign_out
    sign_in_as(other)
    assert_difference -> { other.document_imports.count }, 1 do
      post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    end
  end

  test "server-side rejects an unsupported file type" do
    assert_no_difference -> { DocumentImport.count } do
      post document_imports_url,
           params: { document_import: { files: [ fixture_file_upload("imports/sample.png", "image/png") ] } }
    end
    assert_match I18n.t("document_imports.upload.bad_type"), flash[:alert]
  end

  test "server-side rejects an oversize file" do
    big = Tempfile.new([ "big", ".csv" ])
    big.write("a" * (DocumentImport::MAX_FILE_BYTES + 1))
    big.rewind
    assert_no_difference -> { DocumentImport.count } do
      post document_imports_url,
           params: { document_import: { files: [ Rack::Test::UploadedFile.new(big.path, "text/csv") ] } }
    end
    assert_match I18n.t("document_imports.upload.too_large"), flash[:alert]
  ensure
    big&.close!
  end

  test "the 11th upload of the day is capped with no new record" do
    10.times { |i| @user.document_imports.new(checksum: "seed-#{i}-#{SecureRandom.hex}").save!(validate: false) }
    assert_no_difference -> { @user.document_imports.count } do
      post document_imports_url, params: { document_import: { files: [ csv_upload ] } }
    end
    assert_equal I18n.t("document_imports.create.daily_cap", max: DocumentImport::MAX_PER_DAY), flash[:alert]
  end

  test "posting no files redirects with the no_files alert" do
    post document_imports_url, params: { document_import: { files: [ "" ] } }
    assert_equal I18n.t("document_imports.create.no_files"), flash[:alert]
  end

  test "status frame lists non-dismissed imports and flags active while non-terminal" do
    make_import(@user)
    get status_document_imports_url
    assert_response :success
    assert_select "turbo-frame#import_status"
    assert_select '[data-import-active="true"]'
  end

  test "destroy dismisses the import and purges the blob" do
    di = make_import(@user)
    perform_enqueued_jobs { delete document_import_url(di) }
    assert_equal "dismissed", di.reload.status
    assert_not di.file.attached?
  end

  test "cannot dismiss another user's import" do
    other = User.create!(email_address: "o2@example.com", password: "password123")
    di = make_import(other)
    delete document_import_url(di)
    assert_response :not_found
    assert_not di.reload.dismissed?
  end

  test "the onboarding accounts step renders the upload hero and the untouched manual form" do
    get onboarding_step_url("accounts")
    assert_response :success
    assert_select "[data-controller='import-upload']"
    assert_select "turbo-frame#import_status"
    assert_select "#bank_accounts_list" # manual path unchanged
  end

  test "deterministic slice: upload OFX → review pre-checked → apply → account in the wizard list" do
    stub_classifier do
      perform_enqueued_jobs do
        post document_imports_url,
             params: { document_import: { files: [ fixture_file_upload("imports/nubank.ofx", "application/x-ofx") ] } }
      end
    end
    import = @user.document_imports.last
    assert_equal "extracted", import.status
    assert import.proposals.any? { it["kind"] == "bank_account" }

    get review_document_imports_url
    assert_response :success
    assert_select "input[type=checkbox][checked=checked]" # ≥0.8 renders pre-checked

    pid = import.proposals.find { it["kind"] == "bank_account" }["pid"]
    assert_difference -> { @user.bank_accounts.count }, 1 do
      post apply_document_imports_url, params: { check: { pid => "1" } }
    end
    assert_redirected_to onboarding_step_url("accounts")
    assert_equal 357625, @user.bank_accounts.last.balance_cents
    assert_equal "applied", import.reload.proposals.find { it["kind"] == "bank_account" }["state"]

    get onboarding_step_url("accounts")
    assert_select "#bank_accounts_list", text: /.+/
  end

  test "review renders every group including the commitment subgroups" do
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx", status: "uploaded")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")), filename: "n.ofx", content_type: "application/x-ofx")
    import.save!
    import.update!(status: "extracted", proposals: full_review_proposals)

    get review_document_imports_url
    assert_response :success
    assert_select "h2", text: I18n.t("document_imports.review.groups.incomes")
    assert_select "h3", text: I18n.t("document_imports.review.groups.installments")
    assert_select "h3", text: I18n.t("document_imports.review.groups.subscriptions")
    assert_select "input[name=?]", "edits[inc1][amount_reais]" # income amount is editable
  end

  test "unlock decrypts with the password in-request, re-enqueues, and never stores the password" do
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "pdf",
                                        status: "failed", error_code: "password_protected")
    import.file.attach(io: File.open(file_fixture("imports/statement.pdf")),
                       filename: "enc.pdf", content_type: "application/pdf")
    import.save!

    seen = nil
    stub_pages = { "pages" => [ "text" ], "page_count" => 1, "text_usable" => true }
    assert_enqueued_with(job: ProcessDocumentImportJob, args: [ import.id ]) do
      Imports::PdfTextExtractor.stub(:call, ->(_bytes, password: nil) { seen = password; stub_pages }) do
        post unlock_document_import_url(import), params: { password: "cpf1234" }
      end
    end

    assert_equal "cpf1234", seen # password used in-request
    import.reload
    assert_equal "uploaded", import.status
    assert_nil import.error_code
    assert_equal [ "text" ], import.extraction["pages"]
    assert_not_includes import.reload.attributes.to_s, "cpf1234" # password not persisted
  end

  test "discard rejects a single proposal without creating a record" do
    import = extracted_ofx_import
    pid = import.proposals.find { it["kind"] == "bank_account" }["pid"]
    assert_no_difference -> { @user.bank_accounts.count } do
      post apply_document_imports_url, params: { discard: pid }
    end
    rejected = import.reload.proposals.find { it["pid"] == pid }
    assert_equal "rejected", rejected["state"]
    assert_equal "extracted", import.status # a sibling commitment is still proposed
  end

  private

  def extracted_ofx_import
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "nubank.ofx", content_type: "application/x-ofx")
    import.extraction = Imports::OfxParser.call(file_fixture("imports/nubank.ofx").read)
    import.save!
    stub_classifier { Imports::ProposalBuilder.call(import) }
    import.reload
  end

  def full_review_proposals
    ref = { "pid" => "acct1" }
    [
      { "pid" => "acct1", "kind" => "bank_account", "state" => "proposed", "confidence" => 0.9,
        "payload" => { "institution_code" => "260", "balance_cents" => 357_625 },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-30", "amount_cents" => 357_625 } ] },
      { "pid" => "inc1", "kind" => "income", "state" => "proposed", "confidence" => 0.7,
        "payload" => { "name" => "Salário", "amount_cents" => 4_802_580, "instrument_ref" => ref },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-03", "amount_cents" => 4_802_580 } ] },
      { "pid" => "fix1", "kind" => "commitment", "state" => "proposed", "confidence" => 0.95,
        "payload" => { "commitment_kind" => "fixed", "name" => "Copel", "amount_cents" => 31_741, "schedule_day" => 22, "instrument_ref" => ref },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-22", "amount_cents" => 31_741 } ] },
      { "pid" => "sub1", "kind" => "commitment", "state" => "proposed", "confidence" => 0.9,
        "payload" => { "commitment_kind" => "subscription", "name" => "Netflix", "amount_cents" => 3_990, "instrument_ref" => ref },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-15", "amount_cents" => 3_990 } ] },
      { "pid" => "ins1", "kind" => "commitment", "state" => "proposed", "confidence" => 0.9,
        "payload" => { "commitment_kind" => "installment", "name" => "Seguro", "amount_cents" => 32_853, "installments_count" => 36, "instrument_ref" => ref },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-05", "amount_cents" => 32_853, "installment" => [ 27, 36 ] } ] }
    ]
  end

  def csv_upload
    fixture_file_upload("imports/sample.csv", "text/csv")
  end

  def make_import(user)
    di = user.document_imports.new(checksum: SecureRandom.hex)
    di.file.attach(io: File.open(file_fixture("imports/sample.csv")),
                   filename: "sample.csv", content_type: "text/csv")
    di.save!
    di
  end
end
