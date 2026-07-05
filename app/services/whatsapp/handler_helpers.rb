module Whatsapp
  # Shared plumbing for the per-intent handlers (07 §4). Each handler is @msg + @extraction in,
  # a command/upsert + WhatsappReply out — the same shape as the shipped Decider.
  module HandlerHelpers
    private

    def user = @msg.user

    def reply(key, txn: nil, **args)
      WhatsappReply.deliver(user: user, key: "whatsapp.replies.#{key}", transaction: txn, **args)
    end

    def currency(cents) = WhatsappReply.currency(cents, locale: user.locale)

    def month_label(date) = I18n.with_locale(user.locale) { I18n.l(date, format: :month_year) }

    def sp_today = Time.current.in_time_zone("America/Sao_Paulo").to_date

    # Idempotent single-row upsert — dedupes on wa_message_id (a replay creates zero rows).
    def upsert_row(**attrs)
      Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.user = user
        t.whatsapp_message = @msg
        t.source = @extraction.source
        attrs.each { |k, v| t.public_send("#{k}=", v) }
      end
    end

    def match_account(phrase)
      return nil if phrase.blank?
      result = Whatsapp::Matcher.match_phrase(user, phrase, kind: :account)
      result.instrument if result.matched? && result.c_match >= Transaction::MATCH_ASSIGN_MIN
    end
  end
end
