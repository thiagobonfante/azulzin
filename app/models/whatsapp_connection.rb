# Singleton row mirroring the sidecar's WhatsApp session status (one commercial number).
# wwebjs LocalAuth owns the real session on the sidecar's disk; Rails only tracks status +
# the transient QR for the admin panel. No session_data here — never store/replay wwebjs
# credentials from Rails. See .plans/whats §6.4.
class WhatsappConnection < ApplicationRecord
  enum :status, {
    disconnected:  "disconnected",
    initializing:  "initializing",
    qr_pending:    "qr_pending",
    authenticated: "authenticated",
    connected:     "connected",
    logged_out:    "logged_out",
    error:         "error"
  }, default: "disconnected", validate: true

  def self.instance = first_or_create!

  # --- webhook event handlers (broadcasts wired in Phase 5 / admin panel) ---

  def update_qr!(qr_data_url)
    update!(status: "qr_pending", qr_data_url: qr_data_url)
    broadcast_status(type: "qr_code", qr_data_url: qr_data_url)
  end

  def mark_connected!(data = {})
    update!(status: "connected", wa_id: data && data["phone_number"],
            qr_data_url: nil, last_connected_at: Time.current, last_seen_at: Time.current)
    broadcast_status(type: "connected")
  end

  def mark_disconnected!(reason = nil)
    update!(status: "disconnected", last_error: reason)
    broadcast_status(type: "disconnected")
  end

  def mark_auth_failed!(error = nil)
    update!(status: "error", last_error: error)
    broadcast_status(type: "auth_failed")
  end

  def connected? = status == "connected"

  private

  # No-op until the ActionCable channel lands in Phase 5; kept here so the event handlers
  # are complete and callers don't change.
  def broadcast_status(payload)
    ActionCable.server.broadcast("whatsapp_connection", payload.merge(status: status))
  rescue StandardError => e
    Rails.logger.warn("WhatsappConnection broadcast skipped: #{e.message}")
  end
end
