require "test_helper"

class DocumentImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  private

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
