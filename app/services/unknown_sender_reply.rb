# Replies once (rate-limited per number) to a sender with no verified azulzin account, so
# the endpoint can't be used as a membership oracle or spam amplifier. No user record, so
# it sends directly via the sidecar in the default locale. Rate window refined in Phase 6.
# See .plans/whats §3.2 / §8.
class UnknownSenderReply
  WINDOW = 6.hours

  def self.throttle(jid)
    digits = jid.to_s.sub(/@c\.us\z/, "").gsub(/\D/, "")
    return if digits.blank?
    key = "wa:unknown_reply:#{digits}"
    return unless Rails.cache.write(key, true, expires_in: WINDOW, unless_exist: true)

    body = I18n.with_locale(I18n.default_locale) { I18n.t("whatsapp.replies.unknown_sender") }
    WhatsappService.send_message(digits, body)
  end
end
