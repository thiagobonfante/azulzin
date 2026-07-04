# Processes one inbound WhatsApp message: extract → (Phase 2: match/score/decide) → reply.
# Serialized PER USER (concurrency key = user_id) so a later reply can never execute before
# the message that created its open ask (Review P0-4). Idempotent: a re-run is a no-op, and
# posting dedupes on source_message_id. See .plans/whats §3.6.
class ProcessInboundWhatsappJob < ApplicationJob
  queue_as :whatsapp

  limits_concurrency to: 1, key: ->(message_id) { WhatsappMessage.where(id: message_id).pick(:user_id) }

  retry_on OpenRouterClient::RateLimited, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(message_id)
    msg = WhatsappMessage.find(message_id)
    return if msg.status == "processed"     # re-run guard (idempotent)
    return if msg.user.nil?                 # defense-in-depth; webhook already short-circuits

    msg.update!(status: "processing")

    text = msg.body                         # Phase 1: text only (audio/image in Phases 3/4)
    extraction = Whatsapp::Extractor.from_text(msg.user, text, modality: "text")

    # Phase 1: no matcher/decider yet — park a pending_review transaction (or ask for the
    # amount if we couldn't read one). Phase 2 replaces this with Matcher → Confidence → Decider.
    if extraction.amount_present?
      txn = park(msg, extraction)
      WhatsappReply.deliver(user: msg.user, key: "whatsapp.replies.parked", transaction: txn)
      msg.update!(status: "processed", processed_at: Time.current)
    else
      WhatsappReply.deliver(user: msg.user, key: "whatsapp.replies.clarify_amount")
      msg.update!(status: "processed", processed_at: Time.current, ai_result: extraction.to_h)
    end
  end

  private

  def park(msg, extraction)
    Transaction.find_or_create_by!(source_message_id: msg.wa_message_id) do |t|
      t.user            = msg.user
      t.whatsapp_message = msg
      t.amount_cents    = extraction.amount_cents
      t.merchant        = extraction.merchant
      t.payment_method  = extraction.payment_method
      t.occurred_on     = extraction.occurred_on || today
      t.status          = "pending_review"
      t.source          = extraction.source
      t.confidence      = (extraction.overall_confidence.to_f * 100).round
      t.extraction      = extraction.to_h.compact
    end
  end

  # "hoje" in the app's zone (America/Sao_Paulo) — never UTC (Review P0-2).
  def today = Time.current.in_time_zone("America/Sao_Paulo").to_date
end
