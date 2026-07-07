module Whatsapp
  # Turns an extraction + match + confidence into an outcome, per the DECIDED silent
  # auto-commit posture (Open Decision #5):
  #   - amount present & confidence ≥ floor & instrument matched strongly → POST assigned
  #   - amount present & confidence ≥ floor & instrument unknown/weak      → POST unassigned
  #   - amount present & confidence < floor                               → PARK (pending_review)
  #   - amount missing                                                    → ASK "quanto foi?"
  # The transaction is idempotent on source_message_id. See .plans/whats §4.7 / §5.
  class Decider
    ASK_TTL = 60.minutes

    def initialize(msg, extraction, match, confidence)
      @msg = msg
      @extraction = extraction
      @match = match
      @confidence = confidence
    end

    def call
      return ask_amount unless @extraction.amount_present?
      @confidence.above_floor? ? post : park
    end

    private

    def post
      instrument = assignable_instrument
      txn = upsert(status: "posted", confirmed_at: Time.current, instrument: instrument)
      # Naming the auto-assigned category in the reply is the cheap correction loop (O2):
      # a wrong silent category becomes visible immediately, not at month-end.
      if instrument && txn.category
        reply("whatsapp.replies.posted_categorized", txn,
              amount: currency, instrument: instrument.display_name, category: txn.category.name)
      elsif instrument
        reply("whatsapp.replies.posted", txn,
              amount: currency, instrument: instrument.display_name)
      else
        reply("whatsapp.replies.posted_unassigned", txn, amount: currency)
      end
      txn
    end

    def park
      txn = upsert(status: "pending_review")
      reply("whatsapp.replies.parked", txn)
      txn
    end

    # Amount unreadable — the ONE WhatsApp question we keep. Store a placeholder open-ask
    # row (amount 0) carrying the already-resolved instrument, so the user's next reply
    # only needs to supply the amount.
    def ask_amount
      txn = upsert(status: "needs_clarification", amount_cents: 0,
                   instrument: assignable_instrument,
                   ask: { "slot" => "amount" }, ask_expires_at: ASK_TTL.from_now)
      reply("whatsapp.replies.clarify_amount", txn)
      txn
    end

    def assignable_instrument
      return nil unless @match.matched? && @match.c_match >= Transaction::MATCH_ASSIGN_MIN
      @match.instrument
    end

    def currency = WhatsappReply.currency(@extraction.amount_cents, locale: @msg.user.locale)

    def upsert(status:, instrument: nil, amount_cents: nil, ask: {}, ask_expires_at: nil, **_)
      Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.account          = account       # D2: tenancy (nil fallback), NOT raw @msg.account
        t.created_by       = @msg.user     # D7: attribution — explicit, never Current.user (job)
        t.whatsapp_message = @msg
        t.amount_cents     = amount_cents || @extraction.amount_cents
        t.merchant         = @extraction.merchant
        t.payment_method   = @extraction.payment_method
        t.occurred_on      = @extraction.occurred_on || today
        # Explicit billing_month write site (02 §3.2-1): the closing rule for a matched card,
        # calendar month otherwise. Computed here, not left solely to the before_validation net.
        t.billing_month    = billing_month_for(instrument, t.occurred_on)
        # R6: memory → LLM label resolved in Ruby (≥ MATCH_MIN), never an LLM id.
        t.category_id, t.category_source =
          Categories.auto_assign(account: account, merchant: @extraction.merchant, label: @extraction.category)
        t.status           = status
        t.confirmed_at     = (Time.current if status == "posted")
        t.source           = @extraction.source
        t.confidence       = @confidence.capture_score
        t.extraction       = @extraction.to_h.compact
        t.match_meta       = { "reason" => @match.reason, "c_match" => @match.c_match }
        t.ask              = ask
        t.ask_expires_at   = ask_expires_at
        assign_instrument(t, instrument)
        # Capture-time subscription reconciliation (05 §5.7 pass 1): a posted card charge similar
        # to an active card subscription/fixed commitment on that card adopts its commitment_id,
        # so the bill projection drops out (no double-count).
        t.commitment_id = link_card_commitment(t) if status == "posted" && instrument.is_a?(CreditCard)
      end
    end

    # "Whose stuff?" → account (spine D6), with the deploy-window nil fallback (doc 04 §3.1/§4).
    def account
      return @msg.account if @msg.account
      @msg.account = @msg.user&.account
      @msg.save! if @msg.account && @msg.persisted?
      @msg.account
    end

    def link_card_commitment(txn)
      card = txn.credit_card
      return nil unless card
      candidates = card.commitments.kept.active.select do |c|
        %w[subscription fixed].include?(c.kind) && c.active_in?(txn.billing_month) &&
          !c.paid_in?(txn.billing_month) && amount_close?(txn.amount_cents, c.amount_cents)
      end
      best = candidates.max_by { |c| Whatsapp.similarity(Whatsapp.normalize(txn.merchant.to_s), Whatsapp.normalize(c.name)) }
      return nil unless best && Whatsapp.similarity(Whatsapp.normalize(txn.merchant.to_s), Whatsapp.normalize(best.name)) >= Transaction::MATCH_ASSIGN_MIN
      best.id
    end

    def amount_close?(a, b)
      tol = [ (b.to_i * 0.2).round, 500 ].max
      (a.to_i - b.to_i).abs <= tol
    end

    def assign_instrument(txn, instrument)
      case instrument
      when BankAccount then txn.bank_account = instrument
      when CreditCard  then txn.credit_card = instrument
      end
    end

    # Card rows follow the closing rule; everything else buckets by calendar month.
    def billing_month_for(instrument, occurred_on)
      instrument.is_a?(CreditCard) ? instrument.billing_month_for(occurred_on) : occurred_on.beginning_of_month
    end

    def reply(key, txn, **args) = WhatsappReply.deliver(user: @msg.user, key: key, transaction: txn, **args)

    def today = Time.current.in_time_zone("America/Sao_Paulo").to_date
  end
end
