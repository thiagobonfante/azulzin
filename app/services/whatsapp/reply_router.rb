module Whatsapp
  # Routes a user's next reply to their single open ask. Under the silent-auto-commit
  # posture the only ask kept is "quanto foi?" (amount), so this is small; the confirm /
  # disambiguation branches live in the plan (§5.3) and slot in here if ever enabled.
  # Transitions are guarded (Review P1-3). See .plans/whats §5.2.
  class ReplyRouter
    def initialize(open_ask, msg, text)
      @ask  = open_ask
      @msg  = msg
      @text = text
    end

    def call
      case @ask.ask["slot"]
      when "amount" then resolve_amount
      else re_ask("whatsapp.replies.clarify_amount")
      end
    end

    private

    def resolve_amount
      cents = Money.to_cents(@text)
      return re_ask("whatsapp.replies.clarify_amount") unless cents&.positive?

      # A user-typed amount is authoritative → post (guarded; no-op if the ask expired).
      posted = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                 status: "posted", amount_cents: cents, confirmed_at: Time.current,
                 ask: {}, ask_expires_at: nil)
      return unless posted

      if @ask.assigned?
        reply("whatsapp.replies.posted", amount: currency(cents), instrument: @ask.instrument.display_name)
      else
        reply("whatsapp.replies.posted_unassigned", amount: currency(cents))
      end
    end

    def currency(cents) = WhatsappReply.currency(cents, locale: @msg.user.locale)
    def reply(key, **args) = WhatsappReply.deliver(user: @msg.user, key: key, transaction: @ask, **args)
    def re_ask(key) = WhatsappReply.deliver(user: @msg.user, key: key)
  end
end
