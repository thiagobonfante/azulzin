# Sends a pt-BR reply to a user through the sidecar, logging it as an outbound
# WhatsappMessage. All copy is an i18n key rendered in the user's locale; money is
# formatted with number_to_currency (never an interpolated R$). Runs from a job, not a
# web request. See .plans/whats §3.5.
class WhatsappReply
  # key: an i18n key under whatsapp.replies.*  ·  transaction: optional link
  def self.deliver(user:, key:, transaction: nil, **i18n_args)
    body = render(user, key, **i18n_args)
    outbound = WhatsappMessage.create!(
      user: user, account: user.account, direction: "outbound", message_type: "text",
      body: body, status: "sent", linked_transaction: transaction
    )
    # Reply to the exact JID we last heard from (kept current by the webhook) so @lid
    # contacts are reachable; fall back to the phone for a not-yet-seen number.
    res = WhatsappService.send_message(user.whatsapp_jid.presence || user.phone, body)
    outbound.update(wa_message_id: res[:id]) if res[:id]
    outbound
  end

  # Format money for a reply body inside the user's locale (no view helper in a job).
  def self.currency(cents, locale:)
    I18n.with_locale(locale) do
      ActionController::Base.helpers.number_to_currency(BigDecimal(cents.to_i) / 100)
    end
  end

  def self.render(user, key, **i18n_args)
    I18n.with_locale(user.locale) { I18n.t(key, **i18n_args) }
  end
end
