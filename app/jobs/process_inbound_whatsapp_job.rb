# Processes one inbound WhatsApp message: extract → (Phase 2: match/score/decide) → reply.
# Serialized PER USER (concurrency key = user_id) so a later reply can never execute before
# the message that created its open ask (Review P0-4). Idempotent: a re-run is a no-op, and
# posting dedupes on source_message_id. See .plans/whats §3.6.
class ProcessInboundWhatsappJob < ApplicationJob
  queue_as :whatsapp

  limits_concurrency to: 1, key: ->(message_id) { WhatsappMessage.where(id: message_id).pick(:user_id) }

  # Every AI-boundary failure retries (transient), then degrades the same way instead of
  # dead-ending (was: only STT degraded; a vision/extraction failure left the message stuck
  # at "processing" with no reply — silence is the one outcome that burns trust). The
  # generic Error handler is declared BEFORE RateLimited so the more specific one (declared
  # later, matched first by rescue_from) keeps its polynomial backoff.
  retry_on OpenRouterClient::Error, wait: 5.seconds, attempts: 3 do |job, error|
    fail_and_tell(job.arguments.first, "ai_failed: #{error.message}", "whatsapp.replies.processing_failed")
  end
  retry_on OpenRouterClient::RateLimited, wait: :polynomially_longer, attempts: 3 do |job, error|
    fail_and_tell(job.arguments.first, "ai_rate_limited: #{error.message}", "whatsapp.replies.processing_failed")
  end
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, wait: 5.seconds, attempts: 3 do |job, error|
    fail_and_tell(job.arguments.first, "ai_transport: #{error.message}", "whatsapp.replies.processing_failed")
  end
  discard_on ActiveJob::DeserializationError

  # STT down/refusing: same degrade, with the audio-specific copy — never enter the money path.
  retry_on Whatsapp::SttClient::Error, wait: 5.seconds, attempts: 3 do |job, error|
    fail_and_tell(job.arguments.first, "stt_failed: #{error.message}", "whatsapp.replies.stt_failed")
  end

  # Mark failed FIRST (a down sidecar must never re-strand the message at "processing"),
  # then tell the user in their language.
  def self.fail_and_tell(message_id, detail, key)
    msg = WhatsappMessage.find_by(id: message_id)
    return unless msg&.user
    msg.update!(status: "failed", error: detail.to_s.first(200), processed_at: Time.current)
    WhatsappReply.deliver(user: msg.user, key: key)
  end

  # Bound AI spend from a chatty or malicious sender. A legit user never sends this many
  # expenses a minute; over the cap we skip the AI call (the message is still stored).
  MAX_INBOUND_PER_MINUTE = 20

  def perform(message_id)
    msg = WhatsappMessage.find(message_id)
    return if msg.status == "processed"     # re-run guard (idempotent)
    return if msg.user.nil?                 # defense-in-depth; webhook already short-circuits

    msg.update!(status: "processing")

    if over_rate_limit?(msg.user)
      return msg.update!(status: "failed", error: "rate_limited", processed_at: Time.current)
    end

    # Sidecar stored the message but couldn't deliver its media (download/attach failure,
    # already logged at the edge): nothing to read — ask for a resend instead of piping an
    # empty body into the AI (was: the generic help menu, a non-sequitur after sending media).
    if msg.message_type != "text" && !msg.media.attached?
      return self.class.fail_and_tell(msg.id, "media_missing", "whatsapp.replies.media_failed")
    end

    text = resolve_text(msg)                # audio → transcript (stored); image → nil; else body

    # Whisper on silence/background noise returns an empty transcript — or hallucinates our
    # own vocab prompt back as a real-looking expense (dropped to "" in transcribe, raw text
    # kept on the row): skip the LLM, reuse the STT-failure copy (WA-CAP-32/32b).
    if msg.type_audio? && text.blank?
      reason = msg.transcription.present? ? "stt_echo" : "stt_empty"
      return self.class.fail_and_tell(msg.id, reason, "whatsapp.replies.stt_failed")
    end

    # A reply routed to the user's single open ask (e.g. the "quanto foi?" answer) never
    # starts a new pipeline. Per-user serialization guarantees the ask already exists.
    if (open = Transaction.open_ask_for(msg.user))
      Whatsapp::ReplyRouter.new(open, msg, text.to_s).call
      return finish(msg)
    end

    # A goal-creation chat in flight (round 3 P6) routes the next text/audio reply
    # deterministically — zero LLM. The txn ask above wins on purpose (short-lived, 60 min,
    # pre-existing); receipts (nil text) fall through to the receipt pipeline untouched.
    if text.present? && (conv = GoalConversation.open_for(msg.user))
      Whatsapp::GoalFlowRouter.new(conv, msg, text).call
      return finish(msg)
    end

    if (msg.type_image? || msg.type_document?) && msg.media.attached?
      # Receipts: the expense path (ReceiptExtractor → Matcher → Confidence → Decider).
      extraction = Whatsapp::ReceiptExtractor.from_message(msg)
      if extraction.not_receipt?
        not_receipt(msg)
      else
        match      = Whatsapp::Matcher.new(msg.account || msg.user.account, extraction).call
        confidence = Whatsapp::Confidence.new(extraction)
        txn = Whatsapp::Decider.new(msg, extraction, match, confidence).call
        attach_receipt(txn, msg)
      end
    else
      # Text / audio: the intent layer (07 §2) — extracts + classifies + dispatches.
      Whatsapp::Interpreter.new(msg, text).call
    end
    finish(msg)
  end

  private

  def resolve_text(msg)
    case msg.message_type
    when "audio"             then transcribe(msg)
    when "image", "document" then nil          # vision reads the image directly
    else msg.body
    end
  end

  def transcribe(msg)
    transcript = Whatsapp::SttClient.transcribe(msg.media)   # media presence guarded in perform
    msg.update!(transcription: transcript)                   # raw text kept for ops/tuning
    return "" if Whatsapp::SttClient.prompt_echo?(transcript) # hallucinated prompt echo → silence
    transcript
  end

  def over_rate_limit?(user)
    user.whatsapp_messages.inbound.where(created_at: 1.minute.ago..).count > MAX_INBOUND_PER_MINUTE
  end

  # Vision found no completed payment in the image. A caption still rides the full text
  # pipeline (a captioned photo of "mercado 84,90" captures fine); without one, say so —
  # never the old "quanto foi?" amount-ask, which parked a junk row AND trapped the user's
  # NEXT message as its answer.
  def not_receipt(msg)
    if msg.body.present?
      Whatsapp::Interpreter.new(msg, msg.body).call
    else
      WhatsappReply.deliver(user: msg.user, key: "whatsapp.replies.not_receipt")
    end
  end

  # up-tier F5 (06 §2a): copy the receipt onto the transaction by referencing the SAME blob
  # — a metadata row, no byte duplication — so it outlives the 60-day WA media purge.
  # Swallow+log like the webhook's media attach: a missing receipt never drops the transaction.
  def attach_receipt(txn, msg)
    return if txn.nil? || txn.receipt.attached?
    txn.receipt.attach(msg.media.blob)
  rescue StandardError => e
    Rails.logger.error("WA receipt attach failed for message #{msg.id}: #{e.message}")
  end

  def finish(msg) = msg.update!(status: "processed", processed_at: Time.current)
end
