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
      when "commitment_pay_confirm" then resolve_commitment_pay_confirm
      when "duplicate_confirm"  then resolve_duplicate_confirm
      when "instrument_pick"    then resolve_instrument_pick
      when "installment_card_pick" then resolve_installment_card_pick
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

    # Numbered card/account pick for a method-narrowed expense (decider ask_instrument_pick).
    # Card picks recompute billing_month by the card's closing rule — the ask row was upserted
    # instrument-less, so it carries the calendar-month bucket.
    def resolve_instrument_pick
      card_kind = @ask.ask["kind"] == "card"
      income = @ask.direction == "income"
      scope = card_kind ? account.credit_cards : account.bank_accounts
      records = scope.kept.in_order_of(:id, @ask.ask["options"]).to_a
      chosen = pick(records) { |r| r.display_name }
      unless chosen
        key = income ? "ask_income_account_pick" : "ask_#{@ask.ask['kind']}_pick"
        return reply("whatsapp.replies.#{key}",
                     amount: currency(@ask.amount_cents), options: numbered_options(records))
      end

      updates = { status: "posted", confirmed_at: Time.current, ask: {}, ask_expires_at: nil,
                  updated_by_id: @msg.user_id }
      updates[card_kind ? :credit_card_id : :bank_account_id] = chosen.id
      updates[:billing_month] = chosen.billing_month_for(@ask.occurred_on) if card_kind
      posted = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES, **updates)
      return unless posted

      if income
        reply("whatsapp.replies.income_posted", amount: currency(@ask.amount_cents),
              instrument: chosen.display_name)
      elsif @ask.category
        reply("whatsapp.replies.posted_#{card_kind ? 'card' : 'account'}_categorized",
              amount: currency(@ask.amount_cents), instrument: chosen.display_name,
              category: @ask.category.name)
      else
        reply("whatsapp.replies.posted_#{card_kind ? 'card' : 'account'}",
              amount: currency(@ask.amount_cents), instrument: chosen.display_name)
      end
    end

    def resolve_installments_count
      count = parse_count(@text)
      return re_ask("whatsapp.replies.ask_installments_count") unless count&.between?(1, 24)
      # A card picked in a chained installment_card_pick lives on the stub; the phrase
      # match is the fallback for the direct count-ask path.
      card = @ask.credit_card ||
             Whatsapp::Matcher.match_phrase(account, @ask.extraction["instrument_phrase"]).instrument
      return re_ask("whatsapp.replies.ask_installments_count") unless card.is_a?(CreditCard)
      create_installments(card, count)
    end

    # Card pick for a "parcelado" with no card named (installment_decider ask_card_pick);
    # chains into the count ask when the count is missing too (fresh TTL, like chain_missing_leg).
    def resolve_installment_card_pick
      records = account.credit_cards.kept.in_order_of(:id, @ask.ask["options"]).to_a
      chosen = pick(records) { |r| r.display_name }
      unless chosen
        return reply("whatsapp.replies.ask_card_pick", amount: currency(@ask.amount_cents),
                     options: numbered_options(records))
      end
      count = @ask.extraction["installments_count"].to_i
      return create_installments(chosen, count) if count.between?(1, 24)

      chained = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                  credit_card_id: chosen.id, ask: { "slot" => "installments_count" },
                  ask_expires_at: 60.minutes.from_now, updated_by_id: @msg.user_id)
      return unless chained
      reply("whatsapp.replies.ask_installments_count")
    end

    def create_installments(card, count)
      data = @ask.extraction
      total = Money.to_cents(data["installment_total_raw"]) ||
              (Money.to_cents(data["installment_parcel_raw"]).to_i * count).nonzero? ||
              @ask.amount_cents
      @ask.update!(status: "superseded", updated_by: user)
      commitment = Installments::Create.call(account: account, created_by: user, card: card, total_cents: total, count: count,
        occurred_on: @ask.occurred_on, merchant: @ask.merchant, source_message_id: nil)
      # starts_on is the first fatura (parcels are computed occurrences — there are no posted
      # payment rows to scan; the old payments.minimum(:billing_month) was always nil and
      # crashed month_label on every count-ask resolution).
      reply("whatsapp.replies.installments_posted", count: count, parcel: currency(commitment.amount_cents),
            instrument: card.display_name, month: month_label(commitment.starts_on))
    end

    def resolve_commitment_pick
      commitments = account.commitments.kept.in_order_of(:id, @ask.ask["options"]).to_a   # prompt order
      chosen = pick(commitments) { |c| c.name }
      unless chosen   # re-ask with the numbered options (the template interpolates %{options})
        return re_ask("whatsapp.replies.ask_commitment_pick",
                      options: commitments.each_with_index.map { |c, i| "#{i + 1}. #{c.name}" }.join("\n"))
      end
      month = Date.parse(@ask.ask["month"])
      month = chosen.last_month.beginning_of_month if @ask.ask["last_parcel"] && chosen.installment? && chosen.last_month
      if chosen.card?   # card commitments settle on the bill — same guard as the decider
        @ask.update!(status: "superseded", updated_by: user)
        return reply("whatsapp.replies.commitment_on_bill",
                     instrument: chosen.credit_card.display_name, name: chosen.name)
      end
      if chosen.paid_in?(month)
        @ask.update!(status: "superseded", updated_by: user)
        return reply("whatsapp.replies.commitment_already_paid", name: chosen.name, month: month_label(month))
      end
      # Future parcel → chain into the value confirmation (same flow as the direct path).
      if month > sp_today.beginning_of_month
        chained = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                    ask: { "slot" => "commitment_pay_confirm", "commitment_id" => chosen.id,
                           "month" => month.strftime("%Y-%m-%d"), "expected_cents" => chosen.amount_cents },
                    ask_expires_at: 60.minutes.from_now, updated_by_id: @msg.user_id)
        return unless chained
        return reply("whatsapp.replies.ask_pay_confirm", name: chosen.name,
                     month: month_label(month), amount: currency(chosen.amount_cents))
      end
      finalize_commitment_pay(chosen, month, nil)
    end

    # Value confirmation for a future/última parcel: *sim/confirmo* pays the expected (or the
    # doubted) amount; a number pays that value when plausible — a close parcel (≤1 month out)
    # tolerates ±20%, a far one ±50% (early-payoff discounts) — else we doubt once and hold.
    def resolve_commitment_pay_confirm
      commitment = account.commitments.kept.find_by(id: @ask.ask["commitment_id"])
      unless commitment
        @ask.update!(status: "superseded", updated_by: user)
        return reply("whatsapp.replies.commitment_not_found")
      end
      month    = Date.parse(@ask.ask["month"])
      expected = @ask.ask["expected_cents"].to_i

      if Whatsapp.normalize(@text).match?(/\A(sim|confirmo|confirma|confirmar|ok|isso|yes|confirm)\b/)
        finalize_commitment_pay(commitment, month, (@ask.ask["pending_cents"] || expected).to_i,
                                expected: expected)
      elsif (cents = Money.to_cents(@text))&.positive?
        if pay_amount_plausible?(cents, expected, month)
          finalize_commitment_pay(commitment, month, cents, expected: expected)
        else
          @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
            ask: @ask.ask.merge("pending_cents" => cents), ask_expires_at: 60.minutes.from_now,
            updated_by_id: @msg.user_id)
          reply("whatsapp.replies.pay_confirm_doubt", value: currency(cents),
                month: month_label(month), expected: currency(expected))
        end
      else
        reply("whatsapp.replies.ask_pay_confirm", name: commitment.name,
              month: month_label(month), amount: currency(expected))
      end
    end

    # "É um gasto novo?" — *sim* posts the held stub as-is; *não* discards it.
    def resolve_duplicate_confirm
      norm = Whatsapp.normalize(@text)
      if norm.match?(/\A(sim|s|isso|novo|yes)\b/)
        posted = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                   status: "posted", confirmed_at: Time.current, ask: {}, ask_expires_at: nil,
                   updated_by_id: @msg.user_id)
        return unless posted
        if @ask.assigned?
          kind = @ask.credit_card_id ? "card" : "account"
          if @ask.category
            reply("whatsapp.replies.posted_#{kind}_categorized", amount: currency(@ask.amount_cents),
                  instrument: @ask.instrument.display_name, category: @ask.category.name)
          else
            reply("whatsapp.replies.posted_#{kind}", amount: currency(@ask.amount_cents),
                  instrument: @ask.instrument.display_name)
          end
        else
          reply("whatsapp.replies.posted_unassigned", amount: currency(@ask.amount_cents))
        end
      elsif norm.match?(/\A(nao|n|cancela|descarta|no)\b/)
        discarded = @ask.guarded_update(Transaction::OPEN_ASK_STATUSES,
                      status: "superseded", ask: {}, ask_expires_at: nil, updated_by_id: @msg.user_id)
        return unless discarded
        reply("whatsapp.replies.duplicate_discarded")
      else
        label = @ask.merchant.presence || @ask.instrument&.display_name ||
                I18n.t("whatsapp.replies.no_description", locale: user.locale)
        reply("whatsapp.replies.ask_duplicate", amount: currency(@ask.amount_cents), label: label)
      end
    end

    def pay_amount_plausible?(cents, expected, month)
      return true if expected.zero?
      months_ahead = (month.year * 12 + month.month) - (sp_today.year * 12 + sp_today.month)
      pct = months_ahead <= 1 ? 20 : 50
      (cents - expected).abs * 100 <= expected * pct
    end

    def finalize_commitment_pay(commitment, month, amount, expected: nil)
      @ask.update!(status: "superseded", updated_by: user)
      txn = Commitments::MarkPaid.call(commitment, month, amount: amount, created_by: user)
      # Paying ahead for less than the parcel = a discount worth naming, same message.
      saved = expected ? expected - txn.amount_cents : 0
      footer = saved.positive? ? { footer_key: "whatsapp.replies.advance_saving_note",
                                   footer_args: { saved: currency(saved) } } : {}
      if commitment.completed?
        reply("whatsapp.replies.commitment_completed", amount: currency(txn.amount_cents),
              name: commitment.name, month: month_label(month), count: commitment.installments_count, **footer)
      elsif commitment.installment?
        # remaining = parcels actually unpaid, never positional (an advanced última must
        # not read "faltam 0" while earlier parcels are open).
        remaining = commitment.installments_count - commitment.paid_count
        reply("whatsapp.replies.commitment_paid", amount: currency(txn.amount_cents), name: commitment.name,
              month: month_label(month), remaining: remaining, count: commitment.installments_count, **footer)
      else
        reply("whatsapp.replies.commitment_paid_simple", amount: currency(txn.amount_cents),
              name: commitment.name, month: month_label(month), **footer)
      end
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
