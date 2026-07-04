require "test_helper"

class Admin::WhatsappConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:confirmed)
    @admin.update!(name: "Admin", phone: "5511912345678", onboarded_at: Time.current, admin: true)
  end

  # Onboarded non-admin: require_onboarding passes, so require_admin is what redirects.
  def non_admin
    users(:english).tap { |u| u.update!(name: "Reg", phone: "5511911112222", onboarded_at: Time.current, admin: false) }
  end

  test "a non-admin is redirected to the dashboard with an alert" do
    sign_in_as(non_admin)
    get admin_whatsapp_connection_url
    assert_redirected_to dashboard_path
    assert_equal I18n.t("admin.not_authorized"), flash[:alert]
  end

  test "an admin sees the connection panel" do
    sign_in_as(@admin)
    get admin_whatsapp_connection_url
    assert_response :success
    assert_select "#qr-code-display"
  end

  test "reconnect kicks the sidecar and marks the connection initializing" do
    sign_in_as(@admin)
    WhatsappService.stub(:initialize_session, -> { { error: nil } }) do
      post reconnect_admin_whatsapp_connection_url
    end
    assert_redirected_to admin_whatsapp_connection_path
    assert_equal "initializing", WhatsappConnection.instance.status
    assert flash[:notice].present?
  end

  test "reconnect surfaces a sidecar error as an alert" do
    sign_in_as(@admin)
    WhatsappService.stub(:initialize_session, -> { { error: "boom" } }) do
      post reconnect_admin_whatsapp_connection_url
    end
    assert_redirected_to admin_whatsapp_connection_path
    assert flash[:alert].present?
  end

  test "logout disconnects the sidecar and marks the connection logged_out" do
    sign_in_as(@admin)
    WhatsappConnection.instance.update!(status: "connected")
    WhatsappService.stub(:disconnect, -> { { error: nil } }) do
      delete logout_admin_whatsapp_connection_url
    end
    assert_redirected_to admin_whatsapp_connection_path
    assert_equal "logged_out", WhatsappConnection.instance.status
  end
end
