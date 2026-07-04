# Streams sidecar liveness (up/down) to the admin panel. WhatsappServiceHealthCheckJob is
# what broadcasts on a state flip; this channel only streams. Admin-only for the same reason
# as WhatsappConnectionChannel. See 07 §7.4 / §7.7.
class WhatsappServiceStatusChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_user&.admin?
    stream_from "whatsapp_service_status"
  end
end
