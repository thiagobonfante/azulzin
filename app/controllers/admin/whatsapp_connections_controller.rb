# Manage the single commercial WhatsApp connection: scan the QR, watch live status, and
# reconnect/logout. The QR + connection events stream over ActionCable (the Stimulus
# controller subscribes); this controller only kicks the sidecar and renders server state.
# See 07 §7.3.
class Admin::WhatsappConnectionsController < Admin::BaseController
  def show
    @connection = WhatsappConnection.instance
    @service_up = service_up?
  end

  def reconnect
    WhatsappConnection.instance.update!(status: "initializing")
    res = WhatsappService.initialize_session
    if res[:error]
      redirect_to admin_whatsapp_connection_path, alert: t(".failed")
    else
      redirect_to admin_whatsapp_connection_path, notice: t(".initializing")
    end
  rescue StandardError => e
    WhatsappConnection.instance.update!(status: "disconnected", last_error: e.message)
    redirect_to admin_whatsapp_connection_path, alert: t(".failed")
  end

  def logout
    WhatsappService.disconnect
    WhatsappConnection.instance.mark_logged_out!
    redirect_to admin_whatsapp_connection_path, notice: t(".logged_out")
  rescue StandardError => e
    WhatsappConnection.instance.update!(last_error: e.message)
    redirect_to admin_whatsapp_connection_path, alert: t(".failed")
  end

  private

  # The cache (kept warm every ~30s by WhatsappServiceHealthCheckJob, and live-updated over
  # ActionCable) is authoritative when present. When it's cold — a fresh boot, or dev, where
  # the recurring job doesn't run — fall back to a live probe so the badge is accurate on
  # load instead of defaulting to "down".
  def service_up?
    cached = Rails.cache.read(WhatsappServiceHealthCheckJob::CACHE_KEY)
    cached.nil? ? WhatsappService.health_check : cached
  end
end
