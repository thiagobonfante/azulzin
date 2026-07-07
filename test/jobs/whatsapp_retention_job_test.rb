require "test_helper"

class WhatsappRetentionJobTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  def make_message(wa_id, transcription:, age: nil)
    m = WhatsappMessage.create!(user: @user, account: @user.account, direction: "inbound", message_type: "audio",
          wa_message_id: wa_id, transcription: transcription, status: "processed")
    m.media.attach(io: StringIO.new("bytes"), filename: "a.ogg", content_type: "audio/ogg")
    m.update_column(:created_at, age.ago) if age
    m
  end

  test "purges media + transcripts older than the window, keeps recent ones" do
    old    = make_message("old", transcription: "gastei 10", age: 90.days)
    recent = make_message("new", transcription: "gastei 20")

    assert_equal 1, WhatsappRetentionJob.new.perform

    old.reload
    assert_not old.media.attached?
    assert_nil old.transcription
    recent.reload
    assert recent.media.attached?, "recent media should be kept"
    assert_equal "gastei 20", recent.transcription
  end

  # A receipt-image message whose blob may also back a transaction's durable receipt (F5).
  def make_image_message(wa_id, age: 90.days)
    m = WhatsappMessage.create!(user: @user, account: @user.account, direction: "inbound",
          message_type: "image", wa_message_id: wa_id, status: "processed")
    m.media.attach(io: File.open(file_fixture("receipt.jpg")), filename: "receipt.jpg", content_type: "image/jpeg")
    m.update_column(:created_at, age.ago) if age
    m
  end

  def make_receipt_transaction(msg)
    txn = Transaction.create!(account: @user.account, amount_cents: 1_323, occurred_on: Date.current,
                              status: "posted", whatsapp_message: msg)
    txn.receipt.attach(msg.media.blob)   # the F5 blob copy — same blob, no byte duplication
    txn
  end

  # up-tier F5 (06 §4/§6): the 60-day purge must not orphan a blob the transaction still
  # references — the job detaches the WA side and leaves the shared blob alone.
  test "a media blob shared with a transaction receipt survives the purge (detached, not purged)" do
    msg  = make_image_message("shared")
    txn  = make_receipt_transaction(msg)
    blob = msg.media.blob

    WhatsappRetentionJob.new.perform

    assert_not msg.reload.media.attached?, "WA media must still be purged at 60 days (LGPD)"
    assert txn.reload.receipt.attached?,   "the durable receipt must survive the WA purge"
    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert_equal File.binread(file_fixture("receipt.jpg")), txn.receipt.download
  end

  test "an unshared media blob is fully purged (last reference deletes bytes)" do
    msg  = make_image_message("unshared")
    blob = msg.media.blob
    key  = blob.key

    WhatsappRetentionJob.new.perform

    assert_not msg.reload.media.attached?
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(key)
  end

  test "after the WA purge, hard-destroying the transaction purges the surviving blob" do
    msg  = make_image_message("then-destroy")
    txn  = make_receipt_transaction(msg)
    blob = msg.media.blob
    key  = blob.key

    WhatsappRetentionJob.new.perform    # detaches the WA side; the receipt holds the last reference
    txn.destroy!
    perform_enqueued_jobs               # flush the receipt's dependent :purge_later

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(key), "no orphaned bytes once the last reference dies"
  end

  # The full LGPD cascade with a SHARED blob: account deletion destroys both records; the
  # blob must be purged exactly once, leaving no orphaned receipt blobs or bytes.
  test "account deletion leaves no receipt blobs even when receipt and WA media share one" do
    msg  = make_image_message("cascade", age: nil)
    txn  = make_receipt_transaction(msg)
    blob = msg.media.blob
    key  = blob.key

    @user.account.destroy!
    perform_enqueued_jobs   # both PurgeJobs: first purges, the redundant one discards (RecordNotFound cause)

    assert_not ActiveStorage::Attachment.where(blob_id: blob.id).exists?
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(key)
  end

  # Under tenancy the LGPD cascade lives on Account (spine D8): erasing a household = destroying
  # the Account, which takes its WhatsApp messages, media, and transactions with it. Destroying a
  # single user only nulls attribution (covered in user_lgpd_test).
  test "deleting the account erases its WhatsApp messages, media, and transactions (LGPD)" do
    perform_enqueued_jobs do
      msg = make_message("lgpd", transcription: "sensível")
      txn = Transaction.create!(account: @user.account, amount_cents: 100, occurred_on: Date.current, whatsapp_message: msg)

      @user.account.destroy!

      assert_not WhatsappMessage.exists?(msg.id)
      assert_not Transaction.exists?(txn.id)
      assert_not ActiveStorage::Attachment.exists?(record_type: "WhatsappMessage", record_id: msg.id)
    end
  end

  include ActiveJob::TestHelper
end
