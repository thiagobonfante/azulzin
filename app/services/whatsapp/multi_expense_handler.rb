module Whatsapp
  # One message carrying SEVERAL expenses ("197 roupas, 11,22 pedágio, 55,90 almoço crédito
  # santander"). Same silent-auto-commit posture as the single-expense Decider PER ITEM, but
  # ONE reply for the whole batch — never a message per item. Rules:
  #   - exactly one instrument named anywhere → it applies to every item;
  #   - per-item instruments win when several are named;
  #   - one unresolved item in a message that names instruments → post the rest, ONE numbered
  #     ask for that item (resolved via ReplyRouter "multi_instrument_pick");
  #   - two or more unresolved → post NOTHING, ask the user to resend with the banks spelled out;
  #   - no instrument named at all → post unassigned, same as a single bare message.
  # Rows are idempotent on "<wa_message_id>#<index>" (the batch twin of the Decider's dedupe).
  class MultiExpenseHandler
    include HandlerHelpers

    # Payment methods that imply an instrument exists ("dinheiro" doesn't name one).
    INSTRUMENT_METHODS = %w[debito credito pix].freeze

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      items = Array(@extraction.items).map { |it| Extractor.build_item(it, @extraction) }
                                      .select(&:amount_present?)
      # Degenerate split (0–1 usable items): the parent's top-level fields describe the
      # first/only expense — run the untouched single path.
      if items.size < 2
        match = Matcher.new(account, @extraction).call
        return Decider.new(@msg, @extraction, match, Confidence.new(@extraction)).call
      end

      inherit_sole_instrument(items)
      plans = items.each_with_index.map { |ex, i| plan_for(ex, i) }
      doubts = plans.select { |p| p[:outcome] == :doubt }
      return reply("multi_specify") if doubts.size >= 2

      txns = plans.reject { |p| p[:outcome] == :doubt }.map { |p| write(p) }
      if (doubt = doubts.first)
        stub = write_doubt_stub(doubt)
        reply("multi_ask_instrument", txn: stub,
              amount: currency(doubt[:extraction].amount_cents), label: label_for(doubt[:extraction]),
              options: numbered_options(doubt[:candidates]))
      else
        self.class.deliver_summary(user, txns)
      end
    end

    # The batch confirmation — also sent by ReplyRouter when the batch's one ask resolves.
    def self.deliver_summary(user, txns)
      lines = txns.map { |t| summary_line(user, t) }.join("\n")
      WhatsappReply.deliver(user: user, key: "whatsapp.replies.multi_posted",
                            count: txns.size, lines: lines)
    end

    def self.summary_line(user, txn)
      I18n.with_locale(user.locale) do
        amount = WhatsappReply.currency(txn.amount_cents, locale: user.locale)
        label  = txn.merchant.presence || I18n.t("whatsapp.replies.no_description")
        if txn.status == "pending_review"
          I18n.t("whatsapp.replies.multi_line_parked", amount: amount, label: label)
        elsif txn.instrument
          I18n.t("whatsapp.replies.multi_line_posted", amount: amount, label: label,
                                                       instrument: txn.instrument.display_name)
        else
          I18n.t("whatsapp.replies.multi_line_unassigned", amount: amount, label: label)
        end
      end
    end

    # Every row of a batch, in message order (the "#<index>" suffix is the order).
    def self.batch_rows(account, wa_message_id)
      prefix = Transaction.sanitize_sql_like(wa_message_id.to_s)
      account.transactions.kept.where("source_message_id LIKE ?", "#{prefix}#%")
             .sort_by { |t| t.source_message_id[/\d+\z/].to_i }
    end

    private

    # Exactly one distinct instrument spec across the message → it was meant for everything
    # ("…, 55,90 almoço crédito santander" → tudo no santander). Items that say anything
    # themselves keep their own words; several distinct specs → no inheritance.
    def inherit_sole_instrument(items)
      specs = items.select { |ex| instrument_info?(ex) }
      return if specs.empty? || specs.size == items.size
      distinct = specs.map { |ex| [ Whatsapp.normalize(ex.instrument_phrase.to_s), ex.payment_method ] }.uniq
      return unless distinct.size == 1
      (items - specs).each do |ex|
        ex.instrument_phrase = specs.first.instrument_phrase
        ex.payment_method    = specs.first.payment_method
      end
    end

    def instrument_info?(ex)
      ex.instrument_named? || INSTRUMENT_METHODS.include?(ex.payment_method)
    end

    # Per-item Decider#post parity: strong match assigns; a method/phrase-narrowed sole
    # candidate assigns; several candidates would ask — here that's a :doubt. The one multi
    # twist: a bare item in a message that names instruments elsewhere is a doubt too (the
    # user is being specific — never guess), offered every instrument. Below the confidence
    # floor the item parks exactly like a single message (the review tray IS the confirm).
    def plan_for(ex, index)
      match      = Matcher.new(account, ex).call
      confidence = Confidence.new(ex)
      instrument = (match.instrument if match.matched? && match.c_match >= Transaction::MATCH_ASSIGN_MIN)
      candidates = nil
      if instrument.nil? && confidence.above_floor?
        cands = Decider.method_candidates(account, ex)
        if cands.size == 1
          instrument = cands.first
        elsif cands.size > 1
          candidates = cands
        elsif message_names_instruments?
          candidates = all_instruments
        end
      end
      outcome = if !confidence.above_floor? then :park
      elsif candidates.present?             then :doubt
      else                                       :post
      end
      { extraction: ex, match: match, confidence: confidence, instrument: instrument,
        candidates: candidates, outcome: outcome, index: index }
    end

    def message_names_instruments?
      return @names if defined?(@names)
      @names = Array(@extraction.items).any? do |it|
        it["instrument_phrase"].present? || INSTRUMENT_METHODS.include?(it["payment_method"])
      end
    end

    # Same order the user sees in a mixed pick: accounts first, then cards (savings never
    # a candidate — Decider parity).
    def all_instruments = Decider.checking_accounts(account) + Decider.cards(account)

    def write(plan)
      Decider.write(
        msg: @msg, account: account, extraction: plan[:extraction],
        confidence_score: plan[:confidence].capture_score,
        match_meta: { "reason" => plan[:match].reason, "c_match" => plan[:match].c_match },
        source_message_id: item_source_id(plan[:index]),
        status: plan[:outcome] == :park ? "pending_review" : "posted",
        instrument: plan[:instrument])
    end

    # Type-tagged options (cards and accounts can mix in one pick — ids collide across tables).
    def write_doubt_stub(plan)
      options = plan[:candidates].map { |c| "#{c.is_a?(CreditCard) ? 'cc' : 'ba'}:#{c.id}" }
      Decider.write(
        msg: @msg, account: account, extraction: plan[:extraction],
        confidence_score: plan[:confidence].capture_score,
        match_meta: { "reason" => plan[:match].reason, "c_match" => plan[:match].c_match },
        source_message_id: item_source_id(plan[:index]),
        status: "needs_clarification",
        ask: { "slot" => "multi_instrument_pick", "options" => options, "batch" => @msg.wa_message_id },
        ask_expires_at: Decider::ASK_TTL.from_now)
    end

    def item_source_id(index) = "#{@msg.wa_message_id}##{index}"

    def label_for(ex)
      ex.merchant.presence || I18n.t("whatsapp.replies.no_description", locale: user.locale)
    end
  end
end
