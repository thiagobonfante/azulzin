require "test_helper"

class Api::Whatsapp::WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["WHATSAPP_SERVICE_TOKEN"] = "test-token"
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @headers = { "Authorization" => "Bearer test-token" }
  end

  teardown { ENV.delete("WHATSAPP_SERVICE_TOKEN") }

  def message_payload(**overrides)
    { event: "message_received",
      data: { message_id_serialized: "true_5511999998888@c.us_ABC",
              from: "5511999998888@c.us", to: "5511000000000@c.us",
              body: "gastei 13,23 no mercado", timestamp: 1_700_000_000,
              has_media: false, type: "chat" }.merge(overrides) }
  end

  test "rejects a missing/bad bearer token" do
    post api_whatsapp_webhook_path, params: message_payload, as: :json,
         headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end

  test "verified sender: persists inbound + enqueues the job, and is idempotent on redelivery" do
    assert_difference -> { WhatsappMessage.inbound.count }, 1 do
      assert_enqueued_with(job: ProcessInboundWhatsappJob) do
        post api_whatsapp_webhook_path, params: message_payload, as: :json, headers: @headers
      end
    end
    assert_response :ok

    assert_no_difference -> { WhatsappMessage.count } do
      assert_no_enqueued_jobs(only: ProcessInboundWhatsappJob) do
        post api_whatsapp_webhook_path, params: message_payload, as: :json, headers: @headers
      end
    end
  end

  test "unknown sender: no message, no job, one throttled reply" do
    sent = []
    WhatsappService.stub(:send_message, ->(phone, body) { sent << [ phone, body ]; { id: "x" } }) do
      assert_no_difference -> { WhatsappMessage.count } do
        assert_no_enqueued_jobs do
          post api_whatsapp_webhook_path,
               params: message_payload(from: "5511888887777@c.us"), as: :json, headers: @headers
        end
      end
    end
    assert_response :ok
    assert_equal 1, sent.size
  end

  test "verification handshake: unverified sender texting their code gets verified" do
    pending = users(:unconfirmed)
    pending.update!(phone: "5511777776666")
    code = pending.whatsapp_verification_code!

    WhatsappService.stub(:send_message, ->(_p, _b) { { id: "x" } }) do
      post api_whatsapp_webhook_path,
           params: message_payload(from: "5511777776666@c.us", body: "meu codigo #{code}"),
           as: :json, headers: @headers
    end
    assert_response :ok
    pending.reload
    assert pending.phone_verified?
    assert_equal "5511777776666", pending.whatsapp_id
    assert_nil pending.whatsapp_verification_code
  end

  test "connection events update the singleton" do
    post api_whatsapp_webhook_path,
         params: { event: "qr_code", data: { qr_data_url: "data:image/png;base64,XX" } },
         as: :json, headers: @headers
    assert_response :ok
    assert WhatsappConnection.instance.qr_pending?

    post api_whatsapp_webhook_path,
         params: { event: "connected", data: { phone_number: "5511999998888" } },
         as: :json, headers: @headers
    assert WhatsappConnection.instance.reload.connected?
  end
end
