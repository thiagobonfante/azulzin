module Incomes
  # Marks a recurring income received in a month: one posted income-direction transaction
  # linked by income_id (counts-once, 01 §7.3) — the deposit joins the account balance
  # derivation and the month's entradas. Mirror of Commitments::MarkPaid.
  class MarkReceived
    def self.call(income, month, created_by: nil)
      month = month.beginning_of_month
      existing = income.receipts.posted.kept.find_by(billing_month: month)
      return existing if existing
      income.account.transactions.create!(
        created_by:           created_by,   # in-app: nil ⇒ Attributable stamps Current.user
        income:               income,
        merchant:             income.name,
        direction:            "income",
        status:               "posted",
        confirmed_at:         Time.current,
        amount_cents:         income.amount_cents,
        bank_account_id:      income.bank_account_id,
        occurred_on:          Date.current.in_time_zone("America/Sao_Paulo").to_date,
        billing_month:        month,
        billing_month_manual: true,
        source:               "app"
      )
    end
  end
end
