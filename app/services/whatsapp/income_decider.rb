module Whatsapp
  # income intent (07 §4.2): posts a direction:"income" row, links it to a matching recurring
  # income (R1) so received_in? flips, and defaults the account to the income's when none named.
  class IncomeDecider
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      return ask_amount unless @extraction.amount_present?

      account = match_account(@extraction.instrument_phrase)
      income  = linked_income
      account ||= income&.bank_account
      return park unless Whatsapp::Confidence.new(@extraction).above_floor?

      # Income always lands in a bank account: a sole checking account self-picks;
      # several get a numbered pick (same UX as the expense instrument ask).
      if account.nil?
        candidates = account_candidates
        return ask_account_pick(candidates) if candidates.size > 1
        account = candidates.first
      end

      txn = upsert_row(
        direction: "income", status: "posted", confirmed_at: Time.current,
        amount_cents: @extraction.amount_cents, merchant: @extraction.merchant,
        occurred_on: occurred, billing_month: occurred.beginning_of_month,
        bank_account: account, income: income,
        confidence: Whatsapp::Confidence.new(@extraction).capture_score
      )

      if income
        reply("income_posted_linked", txn: txn, amount: currency(txn.amount_cents),
              instrument: (account || income.bank_account).display_name)
      elsif account
        reply("income_posted", txn: txn, amount: currency(txn.amount_cents), instrument: account.display_name)
      else
        reply("income_posted_unassigned", txn: txn, amount: currency(txn.amount_cents))
      end
      txn
    end

    private

    def occurred = @occurred ||= (@extraction.occurred_on || sp_today)

    # Fuzzy-match the payer/label against the user's active income names (≥ 0.6).
    def linked_income
      term = Whatsapp.normalize(@extraction.merchant.to_s)
      return nil if term.blank?
      best = account.incomes.kept.active.max_by { |i| Whatsapp.similarity(term, Whatsapp.normalize(i.name)) }
      best if best && Whatsapp.similarity(term, Whatsapp.normalize(best.name)) >= 0.6
    end

    def account_candidates
      account.bank_accounts.kept.where.not(kind: "savings").order(:created_at).to_a
    end

    def ask_account_pick(candidates)
      txn = upsert_row(direction: "income", status: "needs_clarification",
                       amount_cents: @extraction.amount_cents, merchant: @extraction.merchant,
                       occurred_on: occurred, billing_month: occurred.beginning_of_month,
                       ask: { "slot" => "instrument_pick", "kind" => "account",
                              "options" => candidates.map(&:id) },
                       ask_expires_at: 60.minutes.from_now)
      reply("ask_income_account_pick", txn: txn, amount: currency(txn.amount_cents),
            options: numbered_options(candidates))
      txn
    end

    def ask_amount
      txn = upsert_row(direction: "income", status: "needs_clarification", amount_cents: 0,
                       occurred_on: sp_today, billing_month: sp_today.beginning_of_month,
                       ask: { "slot" => "amount" }, ask_expires_at: 60.minutes.from_now)
      reply("clarify_amount", txn: txn)
      txn
    end

    def park
      txn = upsert_row(direction: "income", status: "pending_review", amount_cents: @extraction.amount_cents,
                       merchant: @extraction.merchant, occurred_on: occurred, billing_month: occurred.beginning_of_month)
      reply("parked", txn: txn)
      txn
    end
  end
end
