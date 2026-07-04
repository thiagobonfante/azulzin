require "test_helper"

class Admin::WhatsappMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:confirmed)
    @admin.update!(name: "Admin", phone: "5511912345678", onboarded_at: Time.current, admin: true)
  end

  def non_admin
    users(:english).tap { |u| u.update!(name: "Reg", phone: "5511911112222", onboarded_at: Time.current, admin: false) }
  end

  test "a non-admin cannot see the inbound audit" do
    sign_in_as(non_admin)
    get admin_whatsapp_messages_url
    assert_redirected_to dashboard_path
  end

  test "an admin sees recent inbound messages" do
    WhatsappMessage.create!(user: @admin, direction: "inbound", message_type: "text",
                            wa_message_id: "wa-audit-1", body: "gastei 10 no mercado", status: "processed")
    sign_in_as(@admin)
    get admin_whatsapp_messages_url
    assert_response :success
    assert_select "body", text: /gastei 10 no mercado/
  end

  test "an admin can open a single message" do
    msg = WhatsappMessage.create!(user: @admin, direction: "inbound", message_type: "text",
                                  wa_message_id: "wa-audit-2", body: "uber 20", status: "processed")
    sign_in_as(@admin)
    get admin_whatsapp_message_url(msg)
    assert_response :success
  end
end
