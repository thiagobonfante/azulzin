require "test_helper"

class WhatsappConnectionChannelTest < ActionCable::Channel::TestCase
  test "a non-admin subscription is rejected" do
    stub_connection current_user: users(:confirmed)   # admin? is false by default
    subscribe
    assert subscription.rejected?
  end

  test "an admin subscribes and streams connection events" do
    admin = users(:confirmed)
    admin.update!(admin: true)
    stub_connection current_user: admin
    subscribe
    assert subscription.confirmed?
    assert_has_stream "whatsapp_connection"
  end
end
