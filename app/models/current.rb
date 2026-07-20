class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # Where the conversation pipeline's replies land for THIS execution: nil → WhatsApp
  # sidecar, :chat → in-app bubble. Stamped by ProcessInboundWhatsappJob from the inbound
  # message's class; proactive notification jobs never set it, so the spine stays on WA.
  attribute :reply_channel
  delegate :user,    to: :session, allow_nil: true
  delegate :account, to: :user,    allow_nil: true   # spine D2 — the one addition
end
