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

    text = resolve_text(msg)                # audio → transcript (stored); image → nil; else body

    # A reply routed to the user's single open ask (e.g. the "quanto foi?" answer) never
    # starts a new pipeline. Per-user serialization guarantees the ask already exists.
    if (open = Transaction.open_ask_for(msg.user))
      Whatsapp::ReplyRouter.new(open, msg, text.to_s).call
      return finish(msg)
    end

    extraction = extract(msg, text)
    match      = Whatsapp::Matcher.new(msg.user, extraction).call
    confidence = Whatsapp::Confidence.new(extraction)
    Whatsapp::Decider.new(msg, extraction, match, confidence).call
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
    return msg.body unless msg.media.attached?
    transcript = Whatsapp::SttClient.transcribe(msg.media)
    msg.update!(transcription: transcript)
    transcript
  end

  def extract(msg, text)
    if (msg.type_image? || msg.type_document?) && msg.media.attached?
      Whatsapp::ReceiptExtractor.from_message(msg)
    else
      Whatsapp::Extractor.from_text(msg.user, text, modality: msg.type_audio? ? "audio" : "text")
    end
  end

  def finish(msg) = msg.update!(status: "processed", processed_at: Time.current)
end
