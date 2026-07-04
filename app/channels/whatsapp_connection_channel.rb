# Streams the live WhatsApp connection events (QR code + connected/disconnected/auth_failed)
# to the admin panel. The model (WhatsappConnection#update_qr!/mark_*) is what broadcasts;
# this channel only streams. Admin-only: a controller gate alone does NOT protect a
# WebSocket, so we reject non-admins here in #subscribed. See 07 §7.4 / §7.7.
class WhatsappConnectionChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_user&.admin?
    stream_from "whatsapp_connection"
  end
end
