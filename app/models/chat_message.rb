# One bubble in the in-app conversation thread (.plans/mobile/08). STI over
# whatsapp_messages ON PURPOSE: transactions carry provenance through the
# whatsapp_message FK and the pipeline dedupes on wa_message_id in every decider —
# a separate table would fork the pipeline, a subclass rides it unchanged (the
# Whatsapp:: namespace keeps its name for the same reason).
#
# Thread scope is per USER (mirrors WhatsApp — each member has their own conversation;
# money still posts to the shared account with the sender's attribution).
class ChatMessage < WhatsappMessage
  MAX_MEDIA_BYTES = 10.megabytes   # same posture as document imports
  # MediaRecorder in the webview produces audio/mp4 (AAC, WKWebView) or audio/webm
  # (Opus, Android WebView/desktop); attachments are receipt photos or PDFs.
  ALLOWED_MEDIA_TYPES = %w[audio/mp4 audio/webm image/jpeg image/png image/webp
                           image/heic image/heif application/pdf].freeze

  # The pipeline's idempotency primitive (source_message_id dedup in every decider).
  before_validation(unless: :wa_message_id?) { self.wa_message_id = "chat:#{SecureRandom.uuid}" }

  validate :inbound_has_content, if: :inbound?
  validate :media_within_limits

  # The reply bubble: pushed to the sender's thread the moment the pipeline creates it.
  # Prepend, not append — the thread renders newest-first inside flex-col-reverse so the
  # browser keeps the scroll pinned to the bottom natively.
  after_create_commit -> { broadcast_prepend_to [ user, :chat ], target: "chat_messages", partial: "chat/message", locals: { message: self } },
                      if: :outbound?

  def self.thread_for(user, limit: 50)
    where(user: user).order(created_at: :desc, id: :desc).limit(limit)
  end

  # Content type as stored by the browser upload, without codec params
  # ("audio/webm;codecs=opus" → "audio/webm").
  def media_mime = media.attached? ? media.content_type.to_s.split(";").first : nil

  def self.message_type_for(mime)
    case mime
    when %r{\Aaudio/}       then "audio"
    when %r{\Aimage/}       then "image"
    when "application/pdf"  then "document"
    end
  end

  private

  def inbound_has_content
    errors.add(:base, :blank) if body.blank? && !media.attached?
  end

  def media_within_limits
    return unless media.attached?
    errors.add(:media, :too_large) if media.blob.byte_size > MAX_MEDIA_BYTES
    errors.add(:media, :unsupported_type) unless ALLOWED_MEDIA_TYPES.include?(media_mime)
  end
end
