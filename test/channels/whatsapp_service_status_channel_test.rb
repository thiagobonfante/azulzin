require "test_helper"

class WhatsappServiceStatusChannelTest < ActionCable::Channel::TestCase
  test "a non-admin subscription is rejected" do
    stub_connection current_user: users(:confirmed)
    subscribe
    assert subscription.rejected?
  end

  test "an admin subscribes and streams service-status events" do
    admin = users(:confirmed)
    admin.update!(admin: true)
    stub_connection current_user: admin
    subscribe
    assert subscription.confirmed?
    assert_has_stream "whatsapp_service_status"
  end
end
