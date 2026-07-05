module Whatsapp
  # Routes a user's next reply to their single open ask. Zero-LLM — every answer is parsed in
  # Ruby (Money.to_cents, a leading index, or a fuzzy name). Transitions are guarded (Review
  # P1-3); when an ask resolves into a command-owned effect the stub is superseded and the
  # command runs (commands stay the single writer). See 07 §5.
  class ReplyRouter
    def initialize(open_ask, msg, text)
      @ask  = open_ask
      @msg  = msg
      @text = text
    end

    def call
      case @ask.ask["slot"]
      when "amount"             then resolve_amount
      when "transfer_to"        then resolve_transfer_leg(:transfer_to_bank_account_id, "ask_transfer_to")
      when "transfer_from"      then resolve_transfer_leg(:bank_account_id, "ask_transfer_from")
      when "installments_count" then resolve_installments_count
      when "commitment_pick"    then resolve_commitment_pick
      else re_ask("whatsapp.replies.clarify_amount")
      end
    end

    private

    def resolve_amount
      cents = Money.to_cents(@text)
      return re_ask("whatsapp.replies.clarify_amount") unless cents&.positive?

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

    def resolve_transfer_leg(column, re_ask_key)
      account = pick(user.bank_accounts.where(id: @ask.ask["options"]).to_a) { |a| a.display_name }
      return re_ask("whatsapp.replies.#{re_ask_key}") unless account

      posted = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                 column => account.id, status: "posted", confirmed_at: Time.current, ask: {}, ask_expires_at: nil)
      return unless posted

      to = @ask.transfer_to_bank_account
      if to&.savings?
        reply("whatsapp.replies.transfer_saved", amount: currency(@ask.amount_cents), instrument: to.display_name)
      else
        reply("whatsapp.replies.transfer_posted", amount: currency(@ask.amount_cents),
              from: @ask.bank_account&.display_name, to: to&.display_name)
      end
    end

    def resolve_installments_count
      count = parse_count(@text)
      return re_ask("whatsapp.replies.ask_installments_count") unless count&.between?(2, 48)
      data = @ask.extraction
      card = Whatsapp::Matcher.match_phrase(user, data["instrument_phrase"]).instrument
      return re_ask("whatsapp.replies.ask_installments_count") unless card.is_a?(CreditCard)

      total = Money.to_cents(data["installment_total_raw"]) ||
              (Money.to_cents(data["installment_parcel_raw"]).to_i * count).nonzero? ||
              @ask.amount_cents
      @ask.update!(status: "superseded")
      commitment = Installments::Create.call(user: user, card: card, total_cents: total, count: count,
        occurred_on: @ask.occurred_on, merchant: @ask.merchant, source_message_id: nil)
      first = commitment.payments.posted.minimum(:billing_month)
      reply("whatsapp.replies.installments_posted", count: count, parcel: currency(commitment.amount_cents),
            instrument: card.display_name, month: month_label(first))
    end

    def resolve_commitment_pick
      commitments = user.commitments.where(id: @ask.ask["options"]).to_a
      chosen = pick(commitments) { |c| c.name }
      return re_ask("whatsapp.replies.ask_commitment_pick") unless chosen
      month = Date.parse(@ask.ask["month"])
      @ask.update!(status: "superseded")
      txn = Commitments::MarkPaid.call(chosen, month)
      reply("whatsapp.replies.commitment_paid_simple", amount: currency(txn.amount_cents),
            name: chosen.name, month: month_label(month))
    end

    # Parse a leading index into the numbered list, else a fuzzy name match (≥ 0.6).
    def pick(records)
      return nil if records.empty?
      if (idx = @text.to_s.strip[/\A\d+/]&.to_i) && idx.between?(1, records.size)
        return records[idx - 1]
      end
      term = Whatsapp.normalize(@text)
      best = records.max_by { |r| Whatsapp.similarity(term, Whatsapp.normalize(yield(r))) }
      best if best && Whatsapp.similarity(term, Whatsapp.normalize(yield(best))) >= 0.6
    end

    def parse_count(text)
      words = { "duas" => 2, "dois" => 2, "tres" => 3, "quatro" => 4, "cinco" => 5, "seis" => 6,
                "sete" => 7, "oito" => 8, "nove" => 9, "dez" => 10, "doze" => 12 }
      norm = Whatsapp.normalize(text)
      return norm[/\d+/].to_i if norm.match?(/\d/)
      words.each { |w, n| return n if norm.include?(w) }
      nil
    end

    def user = @msg.user
    def currency(cents) = WhatsappReply.currency(cents, locale: user.locale)
    def month_label(date) = I18n.with_locale(user.locale) { I18n.l(date, format: :month_year) }
    def reply(key, **args) = WhatsappReply.deliver(user: user, key: key, transaction: @ask, **args)
    def re_ask(key) = WhatsappReply.deliver(user: user, key: key)
  end
end
