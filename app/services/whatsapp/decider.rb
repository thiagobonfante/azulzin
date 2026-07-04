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
      if instrument
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
        t.user             = @msg.user
        t.whatsapp_message = @msg
        t.amount_cents     = amount_cents || @extraction.amount_cents
        t.merchant         = @extraction.merchant
        t.payment_method   = @extraction.payment_method
        t.occurred_on      = @extraction.occurred_on || today
        t.status           = status
        t.confirmed_at     = (Time.current if status == "posted")
        t.source           = @extraction.source
        t.confidence       = @confidence.capture_score
        t.extraction       = @extraction.to_h.compact
        t.match_meta       = { "reason" => @match.reason, "c_match" => @match.c_match }
        t.ask              = ask
        t.ask_expires_at   = ask_expires_at
        assign_instrument(t, instrument)
      end
    end

    def assign_instrument(txn, instrument)
      case instrument
      when BankAccount then txn.bank_account = instrument
      when CreditCard  then txn.credit_card = instrument
      end
    end

    def reply(key, txn, **args) = WhatsappReply.deliver(user: @msg.user, key: key, transaction: txn, **args)

    def today = Time.current.in_time_zone("America/Sao_Paulo").to_date
  end
end
