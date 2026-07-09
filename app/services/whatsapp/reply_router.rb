module Whatsapp
  # Routes a user's next reply to their single open ask. Zero-LLM — every answer is parsed in
  # Ruby (Money.to_cents, a leading index, or a fuzzy name). Transitions are guarded (Review
  # P1-3); when an ask resolves into a command-owned effect the stub is superseded and the
  # command runs (commands stay the single writer). See 07 §5.
  class ReplyRouter
    include HandlerHelpers   # account/user/currency/month_label + the transfer-leg ask helpers

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
                 ask: {}, ask_expires_at: nil, updated_by_id: @msg.user_id)  # update_all skips the callback (doc 04 §5)
      return unless posted

      if @ask.assigned?
        key = @ask.credit_card_id ? "posted_card" : "posted_account"
        reply("whatsapp.replies.#{key}", amount: currency(cents), instrument: @ask.instrument.display_name)
      else
        reply("whatsapp.replies.posted_unassigned", amount: currency(cents))
      end
    end

    def resolve_transfer_leg(column, re_ask_key)
      # in_order_of preserves the PROMPT order stored in the ask (where(id:) returns PK order,
      # so "4" used to pick whatever row happened to be fourth in the DB).
      records = account.bank_accounts.kept.in_order_of(:id, @ask.ask["options"]).to_a
      bank = pick(records) { |a| a.display_name }
      other_id = column == :transfer_to_bank_account_id ? @ask.bank_account_id : @ask.transfer_to_bank_account_id
      # Unparseable pick, or the same account as the other leg → re-ask with the same options.
      if bank.nil? || bank.id == other_id
        return reply("whatsapp.replies.#{re_ask_key}", options: numbered_options(records))
      end
      # Both legs unmatched at ask time: store this leg and chain an ask for the other one —
      # posting now would persist a half transfer (guarded_update skips transfer_shape).
      return chain_missing_leg(column, bank) if other_id.nil?

      posted = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                 column => bank.id, status: "posted", confirmed_at: Time.current, ask: {}, ask_expires_at: nil,
                 updated_by_id: @msg.user_id)  # update_all skips the callback (doc 04 §5)
      return unless posted

      to = @ask.transfer_to_bank_account
      if to&.savings?
        reply("whatsapp.replies.transfer_saved", amount: currency(@ask.amount_cents), instrument: to.display_name)
      else
        reply("whatsapp.replies.transfer_posted", amount: currency(@ask.amount_cents),
              from: @ask.bank_account&.display_name, to: to&.display_name)
      end
    end

    # Any future ask-resolution path that posts a transfer must repeat the both-legs check
    # above — the model validation can't catch it (guarded_update bypasses callbacks).
    def chain_missing_leg(column, bank)
      other_slot = column == :transfer_to_bank_account_id ? "transfer_from" : "transfer_to"
      accounts = transfer_leg_accounts
      # Fresh ask_expires_at: a chained ask must not be born expired. jsonb type-cast through
      # update_all is fine (precedent: `ask: {}` in resolve_amount).
      chained = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                  column => bank.id, ask: { "slot" => other_slot, "options" => accounts.map(&:id) },
                  ask_expires_at: 60.minutes.from_now, updated_by_id: @msg.user_id)
      return unless chained
      reply("whatsapp.replies.ask_#{other_slot}", options: numbered_options(accounts))
    end

    def resolve_installments_count
      count = parse_count(@text)
      return re_ask("whatsapp.replies.ask_installments_count") unless count&.between?(2, 48)
      data = @ask.extraction
      card = Whatsapp::Matcher.match_phrase(account, data["instrument_phrase"]).instrument
      return re_ask("whatsapp.replies.ask_installments_count") unless card.is_a?(CreditCard)

      total = Money.to_cents(data["installment_total_raw"]) ||
              (Money.to_cents(data["installment_parcel_raw"]).to_i * count).nonzero? ||
              @ask.amount_cents
      @ask.update!(status: "superseded", updated_by: user)
      commitment = Installments::Create.call(account: account, created_by: user, card: card, total_cents: total, count: count,
        occurred_on: @ask.occurred_on, merchant: @ask.merchant, source_message_id: nil)
      first = commitment.payments.posted.kept.minimum(:billing_month)
      reply("whatsapp.replies.installments_posted", count: count, parcel: currency(commitment.amount_cents),
            instrument: card.display_name, month: month_label(first))
    end

    def resolve_commitment_pick
      commitments = account.commitments.kept.in_order_of(:id, @ask.ask["options"]).to_a   # prompt order
      chosen = pick(commitments) { |c| c.name }
      unless chosen   # re-ask with the numbered options (the template interpolates %{options})
        return re_ask("whatsapp.replies.ask_commitment_pick",
                      options: commitments.each_with_index.map { |c, i| "#{i + 1}. #{c.name}" }.join("\n"))
      end
      month = Date.parse(@ask.ask["month"])
      @ask.update!(status: "superseded", updated_by: user)
      txn = Commitments::MarkPaid.call(chosen, month, created_by: user)
      reply("whatsapp.replies.commitment_paid_simple", amount: currency(txn.amount_cents),
            name: chosen.name, month: month_label(month))
    end

    def parse_count(text)
      words = { "duas" => 2, "dois" => 2, "tres" => 3, "quatro" => 4, "cinco" => 5, "seis" => 6,
                "sete" => 7, "oito" => 8, "nove" => 9, "dez" => 10, "doze" => 12 }
      norm = Whatsapp.normalize(text)
      return norm[/\d+/].to_i if norm.match?(/\d/)
      words.each { |w, n| return n if norm.include?(w) }
      nil
    end

    # user/account/currency/month_label come from HandlerHelpers; reply overrides it (full key,
    # always linked to the ask row).
    def reply(key, **args) = WhatsappReply.deliver(user: user, key: key, transaction: @ask, **args)
    def re_ask(key, **args) = WhatsappReply.deliver(user: user, key: key, **args)
  end
end
