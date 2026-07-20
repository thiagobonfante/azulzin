require "test_helper"

# .plans/mobile/05 §4: auth required, type rejection, and the custom-header CSRF stance
# (null_session + X-Azulzin-Capture — browsers can't send it cross-site without a CORS
# preflight we never answer).
class CapturesControllerTest < ActionDispatch::IntegrationTest
  HEADERS = { "X-Azulzin-Capture" => "1" }.freeze

  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", onboarded_at: Time.current)
  end

  test "stores the capture and enqueues the pipeline" do
    sign_in_as(@user)
    assert_enqueued_with(job: ProcessInboundWhatsappJob) do
      post captures_url, headers: HEADERS,
        params: { file: fixture_file_upload("receipt.jpg", "image/jpeg"), caption: "mercado" }
    end
    assert_redirected_to transactions_url
    message = CaptureMessage.sole
    assert_equal @user, message.user
    assert_equal "mercado", message.body
    assert_equal "image", message.message_type
  end

  test "rejects a non-receipt media type" do
    sign_in_as(@user)
    assert_no_enqueued_jobs(only: ProcessInboundWhatsappJob) do
      post captures_url, headers: HEADERS,
        params: { file: fixture_file_upload("audio.webm", "audio/webm") }
    end
    assert_response :unprocessable_entity   # a status the shells can key their toast on
    assert_equal 0, CaptureMessage.count
  end

  test "refuses without the capture header" do
    sign_in_as(@user)
    post captures_url, params: { file: fixture_file_upload("receipt.jpg", "image/jpeg") }
    assert_response :forbidden
  end

  test "requires authentication" do
    post captures_url, headers: HEADERS,
      params: { file: fixture_file_upload("receipt.jpg", "image/jpeg") }
    assert_redirected_to new_session_url
  end
end
