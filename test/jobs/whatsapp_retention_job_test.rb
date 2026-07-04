require "test_helper"

class WhatsappRetentionJobTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  def make_message(wa_id, transcription:, age: nil)
    m = WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "audio",
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

  test "deleting a user erases their WhatsApp messages, media, and transactions (LGPD)" do
    perform_enqueued_jobs do
      msg = make_message("lgpd", transcription: "sensível")
      txn = Transaction.create!(user: @user, amount_cents: 100, occurred_on: Date.current, whatsapp_message: msg)

      @user.destroy!

      assert_not WhatsappMessage.exists?(msg.id)
      assert_not Transaction.exists?(txn.id)
      assert_not ActiveStorage::Attachment.exists?(record_type: "WhatsappMessage", record_id: msg.id)
    end
  end

  include ActiveJob::TestHelper
end
