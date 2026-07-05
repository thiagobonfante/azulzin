module Whatsapp
  # transfer intent incl. "guardar na caixinha" (07 §4.3): one posted transfer row (single-row
  # model). Savings is not a separate intent — a savings-kind destination just gets the 💙 reply.
  class TransferDecider
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      return ask_amount unless @extraction.amount_present?

      to   = match_account(@extraction.to_instrument_phrase) || savings_default
      from = match_account(@extraction.instrument_phrase) || single_checking

      return ask_slot("transfer_to", from: from)   if to.nil?
      return ask_slot("transfer_from", to: to)     if from.nil?
      return park if from == to || !Whatsapp::Confidence.new(@extraction).above_floor?

      txn = upsert_row(direction: "transfer", status: "posted", confirmed_at: Time.current,
                       amount_cents: @extraction.amount_cents, occurred_on: occurred,
                       billing_month: occurred.beginning_of_month,
                       bank_account: from, transfer_to_bank_account: to)
      if to.savings?
        reply("transfer_saved", txn: txn, amount: currency(txn.amount_cents), instrument: to.display_name)
      else
        reply("transfer_posted", txn: txn, amount: currency(txn.amount_cents), from: from.display_name, to: to.display_name)
      end
      txn
    end

    private

    def occurred = @occurred ||= (@extraction.occurred_on || sp_today)

    def savings_default
      return nil unless savings_verb?
      savings = user.bank_accounts.savings
      savings.first if savings.count == 1
    end

    def single_checking
      checking = user.bank_accounts.checking
      checking.first if checking.count == 1
    end

    def savings_verb?
      Whatsapp::Matcher::SAVINGS_RE.match?("#{@extraction.to_instrument_phrase} #{@extraction.instrument_phrase} #{@extraction.merchant}")
    end

    def ask_amount
      txn = upsert_row(direction: "transfer", status: "needs_clarification", amount_cents: 0,
                       occurred_on: sp_today, billing_month: sp_today.beginning_of_month,
                       ask: { "slot" => "amount" }, ask_expires_at: 60.minutes.from_now)
      reply("clarify_amount", txn: txn)
      txn
    end

    # A stub carrying the resolved leg and the numbered options for the missing one (savings first).
    def ask_slot(slot, from: nil, to: nil)
      accounts = user.bank_accounts.includes(:institution).order(kind: :desc, created_at: :asc).to_a
      txn = upsert_row(direction: "transfer", status: "needs_disambiguation", amount_cents: @extraction.amount_cents,
                       occurred_on: occurred, billing_month: occurred.beginning_of_month,
                       bank_account: from, transfer_to_bank_account: to,
                       ask: { "slot" => slot, "options" => accounts.map(&:id) }, ask_expires_at: 60.minutes.from_now)
      reply(slot == "transfer_to" ? "ask_transfer_to" : "ask_transfer_from", txn: txn,
            options: accounts.each_with_index.map { |a, i| "#{i + 1}. #{a.display_name}" }.join("\n"))
      txn
    end

    def park
      txn = upsert_row(direction: "transfer", status: "pending_review", amount_cents: @extraction.amount_cents,
                       occurred_on: occurred, billing_month: occurred.beginning_of_month)
      reply("parked", txn: txn)
      txn
    end
  end
end
