module Whatsapp
  # Shared plumbing for the per-intent handlers (07 §4). Each handler is @msg + @extraction in,
  # a command/upsert + WhatsappReply out — the same shape as the shipped Decider.
  module HandlerHelpers
    private

    def user = @msg.user

    # "Whose stuff?" → account (spine D6). Resilient to a nil stamp (deploy-window message stored
    # by old code, doc 04 §3.1): fall back to the sender's account and back-stamp it so the
    # denormalized history stays consistent — otherwise a nil account_id would hit
    # transactions.account_id NOT NULL and the job would fail permanently (expense lost).
    def account
      return @msg.account if @msg.account
      @msg.account = user&.account
      @msg.save! if @msg.account && @msg.persisted?
      @msg.account
    end

    def reply(key, txn: nil, **args)
      WhatsappReply.deliver(user: user, key: "whatsapp.replies.#{key}", transaction: txn, **args)
    end

    def currency(cents) = WhatsappReply.currency(cents, locale: user.locale)

    def month_label(date) = I18n.with_locale(user.locale) { I18n.l(date, format: :month_year) }

    def sp_today = Time.current.in_time_zone("America/Sao_Paulo").to_date

    # Idempotent single-row upsert — dedupes on wa_message_id (a replay creates zero rows).
    def upsert_row(**attrs)
      Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.account = account         # D2: tenancy — the helper (nil fallback), NOT raw @msg.account
        t.created_by = @msg.user    # D7: attribution — EXPLICIT, never Current.user (job context)
        t.whatsapp_message = @msg
        t.source = @extraction.source
        attrs.each { |k, v| t.public_send("#{k}=", v) }
      end
    end

    def match_account(phrase)
      return nil if phrase.blank?
      result = Whatsapp::Matcher.match_phrase(account, phrase, kind: :account)
      result.instrument if result.matched? && result.c_match >= Transaction::MATCH_ASSIGN_MIN
    end

    # Transfer-leg ask choices (savings first). The stored ask "options" ids and the numbered
    # prompt MUST come from this same ordered array — a numeric reply resolves by prompt
    # position (ReplyRouter reloads with in_order_of to preserve it).
    def transfer_leg_accounts
      account.bank_accounts.kept.includes(:institution).order(kind: :desc, created_at: :asc).to_a
    end

    def numbered_options(records)
      records.each_with_index.map { |r, i| "#{i + 1}. #{r.display_name}" }.join("\n")
    end
  end
end
