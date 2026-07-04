# Pings the WhatsApp sidecar's /health and caches whether it is up, so the admin panel can
# render a service up/down badge without blocking on the sidecar. Runs on a ~30s schedule
# (config/recurring.yml). Broadcasts to the admin panel only when the up/down state flips,
# so a live badge updates without a page reload. See 07 §3.7.
class WhatsappServiceHealthCheckJob < ApplicationJob
  queue_as :whatsapp

  CACHE_KEY = "whatsapp_service:up".freeze
  # A touch longer than the schedule interval, so a missed run reads as "unknown" rather
  # than a stale "up".
  CACHE_TTL = 2.minutes

  def perform
    up       = WhatsappService.health_check
    previous = Rails.cache.read(CACHE_KEY)
    Rails.cache.write(CACHE_KEY, up, expires_in: CACHE_TTL)
    broadcast(up) if previous != up
  end

  private
    def broadcast(up)
      ActionCable.server.broadcast("whatsapp_service_status", { type: "service_status", up: up })
    rescue StandardError => e
      Rails.logger.warn("WhatsappServiceHealthCheck broadcast skipped: #{e.message}")
    end
end
