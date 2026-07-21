# A receipt shared INTO the app (share sheet → POST /captures — .plans/mobile/05).
# STI grandchild ON PURPOSE: it inherits ChatMessage's pipeline plumbing (uuid dedup id,
# media caps, message_type mapping) and rides the WhatsApp pipeline unchanged, but it is
# NOT a conversation turn — Current.reply_channel becomes :capture and every reply is
# suppressed (outcomes surface as transaction states), and the chat thread excludes it.
class CaptureMessage < ChatMessage
  # Shares are receipts: photos or PDFs only (no audio — that's the chat composer's).
  validate :media_is_receiptable, if: :inbound?

  private

  def media_is_receiptable
    return if media_mime&.match?(%r{\Aimage/|\Aapplication/pdf\z})
    errors.add(:media, :invalid)
  end
end
