# Sends a pt-BR reply to a user through the sidecar, logging it as an outbound
# WhatsappMessage. All copy is an i18n key rendered in the user's locale; money is
# formatted with number_to_currency (never an interpolated R$). Runs from a job, not a
# web request. See .plans/whats §3.5.
class WhatsappReply
  # key: an i18n key under whatsapp.replies.*  ·  transaction: optional link  ·
  # footer_key: optional one-line appendix rendered in the same locale (the first-push
  # opt-out courtesy, .plans/up-tier 01 §2)
  def self.deliver(user:, key:, transaction: nil, footer_key: nil, footer_args: {}, **i18n_args)
    body = render(user, key, footer_key: footer_key, footer_args: footer_args, **i18n_args)
    # Conversation-engine adapter (.plans/mobile/08 §1): a pipeline run that started from
    # an in-app chat message replies as a chat bubble (create + Turbo Stream broadcast in
    # the model) — same body, same keys, no sidecar involved.
    if Current.reply_channel == :chat
      return ChatMessage.create!(
        user: user, account: user.account, direction: "outbound", message_type: "text",
        body: body, status: "sent", linked_transaction: transaction
      )
    end
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
  # The amount is always BRL, so the unit is pinned via money.symbol exactly like
  # MoneyHelper#brl — an en-US recipient must never see reais rendered as dollars.
  # whole: true renders whole reais (ceil, MoneyHelper#brl_whole's job-context twin) for
  # the goals surfaces that hide cents (round 3 P1).
  def self.currency(cents, locale:, whole: false)
    amount = whole ? Money.ceil_to_real(cents) : cents
    I18n.with_locale(locale) do
      ActionController::Base.helpers.number_to_currency(
        BigDecimal(amount.to_i) / 100, unit: I18n.t("money.symbol"), precision: whole ? 0 : 2)
    end
  end

  def self.render(user, key, footer_key: nil, footer_args: {}, **i18n_args)
    I18n.with_locale(user.locale) do
      body = I18n.t(key, **i18n_args)
      footer_key ? "#{body}\n#{I18n.t(footer_key, **footer_args)}" : body
    end
  end
end
