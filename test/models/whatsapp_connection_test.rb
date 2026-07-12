require "test_helper"

class WhatsappConnectionTest < ActiveSupport::TestCase
  test "instance is a singleton" do
    a = WhatsappConnection.instance
    b = WhatsappConnection.instance
    assert_equal a.id, b.id
    assert_equal 1, WhatsappConnection.count
  end

  test "event handlers move status and clear the QR on connect" do
    conn = WhatsappConnection.instance
    conn.update_qr!("data:image/png;base64,QRDATA")
    assert conn.qr_pending?
    assert_equal "data:image/png;base64,QRDATA", conn.qr_data_url

    conn.mark_connected!("phone_number" => "5511999998888")
    assert conn.connected?
    assert_nil conn.qr_data_url
    assert_equal "5511999998888", conn.wa_id
    assert conn.last_connected_at.present?

    conn.mark_disconnected!("logout")
    assert conn.disconnected?
    assert_equal "logout", conn.last_error
  end

  # logged_out must broadcast like every other lifecycle event, or the admin panel
  # keeps showing "Conectado" after a phone-side unlink (found live, ch. 9 walk).
  test "mark_logged_out! moves status and broadcasts" do
    conn = WhatsappConnection.instance
    assert_broadcast_on("whatsapp_connection", type: "logged_out", status: "logged_out") do
      conn.mark_logged_out!
    end
    assert conn.logged_out?
  end
end
