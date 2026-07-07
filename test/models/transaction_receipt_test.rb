require "test_helper"

# up-tier F5 (06 §6): receipt validation gates (size, declared type, magic bytes) and the
# hard-destroy purge. The WA blob-copy + retention interplay lives in the job tests.
class TransactionReceiptTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:confirmed)
    @txn  = @user.account.transactions.create!(amount_cents: 1_000, occurred_on: Date.current, status: "posted")
  end

  def attach(fixture:, filename:, content_type:, io: nil)
    @txn.receipt.attach(io: io || File.open(file_fixture(fixture)), filename: filename, content_type: content_type)
  end

  test "attaches a JPEG within the limit" do
    attach(fixture: "receipt.jpg", filename: "nota.jpg", content_type: "image/jpeg")
    assert @txn.reload.receipt.attached?
    assert_equal "image/jpeg", @txn.receipt.content_type
  end

  test "attaches a PDF within the limit" do
    attach(fixture: "receipt.pdf", filename: "nota.pdf", content_type: "application/pdf")
    assert @txn.reload.receipt.attached?
  end

  test "rejects a file over 10 MB" do
    big = StringIO.new("\xFF\xD8\xFF".b + ("0" * (Transaction::MAX_RECEIPT_BYTES + 1)))
    attach(fixture: nil, io: big, filename: "big.jpg", content_type: "image/jpeg")
    assert @txn.errors.of_kind?(:receipt, :too_large)
    assert_not @txn.reload.receipt.attached?
  end

  test "rejects an .exe renamed .jpg by magic bytes (browser MIME lies)" do
    attach(fixture: "receipt_fake.jpg", filename: "nota.jpg", content_type: "image/jpeg")
    assert @txn.errors.of_kind?(:receipt, :unsupported_type)
    assert_not @txn.reload.receipt.attached?
  end

  test "rejects bytes of one allowed format declared as another (PDF posing as webp)" do
    # identify: false keeps the client-declared type, as a direct upload would — the magic
    # bytes must match the DECLARED type's probe, not just any allowed format.
    @txn.receipt.attach(io: File.open(file_fixture("receipt.pdf")), filename: "nota.webp",
                        content_type: "image/webp", identify: false)
    assert @txn.errors.of_kind?(:receipt, :unsupported_type)
    assert_not @txn.reload.receipt.attached?
  end

  test "hard-destroying the transaction purges the receipt blob and its bytes" do
    attach(fixture: "receipt.jpg", filename: "nota.jpg", content_type: "image/jpeg")
    blob    = @txn.receipt.blob
    key     = blob.key
    service = blob.service
    assert service.exist?(key)

    @txn.destroy!
    perform_enqueued_jobs   # flush the dependent :purge_later PurgeJob

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not service.exist?(key), "receipt bytes must be deleted on hard-destroy"
  end
end
