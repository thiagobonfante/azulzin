require "test_helper"

class ChatMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
  end

  test "requires authentication" do
    sign_out
    post chat_messages_url, params: { chat_message: { body: "mercado 10" } }
    assert_redirected_to new_session_url
  end

  test "a text message is stored inbound and enqueues the pipeline job" do
    assert_enqueued_with(job: ProcessInboundWhatsappJob) do
      post chat_messages_url, params: { chat_message: { body: "mercado 10" } }
    end
    msg = ChatMessage.sole
    assert msg.inbound?
    assert_equal "text", msg.message_type
    assert_equal @user, msg.user
    assert_equal @user.account, msg.account
    assert_match(/\Achat:/, msg.wa_message_id)
  end

  test "an empty message is rejected and enqueues nothing" do
    assert_no_enqueued_jobs do
      post chat_messages_url, params: { chat_message: { body: "  " } },
           as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_equal 0, ChatMessage.count
  end

  test "media kind is derived from the content type" do
    { "audio/webm" => "audio", "image/jpeg" => "image", "application/pdf" => "document" }.each do |mime, kind|
      file = fixture_file_upload(mime.start_with?("audio") ? "audio.webm" : "receipt.#{mime == 'application/pdf' ? 'pdf' : 'jpg'}", mime)
      post chat_messages_url, params: { chat_message: { media: file } }
      assert_equal kind, ChatMessage.order(:id).last.message_type, "for #{mime}"
    end
  end

  test "an unsupported content type is rejected" do
    # Active Storage re-identifies the type from the extension, so the fake must LOOK
    # like a video too — a declared-only mismatch gets corrected upstream.
    video = Rack::Test::UploadedFile.new(StringIO.new("not a video"), "video/mp4",
                                         original_filename: "clip.mp4")
    assert_no_enqueued_jobs(only: ProcessInboundWhatsappJob) do
      post chat_messages_url, params: { chat_message: { media: video } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_equal 0, ChatMessage.count
  end

  test "an oversized upload is rejected" do
    huge = Rack::Test::UploadedFile.new(
      StringIO.new("a" * (ChatMessage::MAX_MEDIA_BYTES + 1)), "image/jpeg", original_filename: "big.jpg")
    post chat_messages_url, params: { chat_message: { media: huge } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal 0, ChatMessage.count
  end
end
