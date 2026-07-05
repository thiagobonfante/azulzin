require "test_helper"

class DocumentImportRetentionJobTest < ActiveJob::TestCase
  setup { @user = users(:confirmed) }

  test "purges the blob and extraction of terminal imports older than the window" do
    old     = build_import(status: "applied",   extraction: { "rows" => [ 1 ] })
    fresh   = build_import(status: "applied",   extraction: { "rows" => [ 1 ] })
    pending = build_import(status: "extracted", extraction: { "rows" => [ 1 ] })
    old.update_columns(updated_at: 31.days.ago)
    pending.update_columns(updated_at: 40.days.ago) # extracted is terminal for the job, NOT the product

    DocumentImportRetentionJob.perform_now

    old.reload
    assert_not old.file.attached?, "old terminal blob should be purged"
    assert_equal({}, old.extraction)

    fresh.reload
    assert fresh.file.attached?, "recent terminal import is within the window"
    assert_equal({ "rows" => [ 1 ] }, fresh.extraction)

    pending.reload
    assert pending.file.attached?, "extracted imports awaiting review are never purged"
    assert_equal({ "rows" => [ 1 ] }, pending.extraction)
  end

  test "honors the DEFAULT_RETENTION_DAYS window via retain_days override" do
    imp = build_import(status: "failed", extraction: { "rows" => [ 1 ] })
    imp.update_columns(updated_at: 8.days.ago)
    DocumentImportRetentionJob.perform_now(retain_days: 7)
    imp.reload
    assert_not imp.file.attached?
  end

  private

  def build_import(status:, extraction:)
    di = @user.document_imports.new(checksum: SecureRandom.hex, extraction: extraction)
    di.file.attach(io: File.open(file_fixture("imports/sample.csv")),
                   filename: "sample.csv", content_type: "text/csv")
    di.status = status
    di.save!
    di
  end
end
