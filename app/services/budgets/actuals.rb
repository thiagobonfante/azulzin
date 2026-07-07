module Budgets
  # The per-category month spend map (up-tier 03 §2), extracted from monthly_flow_chart so
  # the hero bar and Budgets::Check read ONE definition of "gastei em X": posted expenses
  # at their billing_month — card purchases included, at the fatura's month (D4) — PLUS the
  # still-unpaid debit commitments folded in by their own category, so the map reflects the
  # full projected month. Incomes and transfers never count (direction: "expense" only).
  #
  # Returns { category_id => integer cents } (nil key = uncategorized spend).
  class Actuals
    # summary: pass an existing MonthSummary to reuse its commitment projection (the
    # helper already builds one for the leftover tail).
    def self.for(account, month, summary: nil)
      summary ||= MonthSummary.new(account, month)
      spend_by_cat = account.transactions.posted_in(summary.month).where(direction: "expense")
                            .group(:category_id).sum(:amount_cents)
      summary.projected_debit_commitments.each do |c|
        spend_by_cat[c.category_id] = spend_by_cat[c.category_id].to_i + c.amount_cents
      end
      spend_by_cat
    end
  end
end
