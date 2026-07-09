module Goals
  # Speed-up (round 3 decision 6): once this month's parcel is paid and the sobra is still
  # ≥ 20% of it (integer math: sobra × 5 ≥ parcel), offer an extra transfer into the caixinha,
  # bounded by the sobra. Purchase goals only — savings_rate has no date to pull earlier.
  # The controller re-derives the offer at POST time; a render-time sobra is never trusted.
  SpeedUpOffer = Data.define(:sobra_cents, :source_bank_account_id, :destination_bank_account_id) do
    def self.for(goal, month: Date.current.in_time_zone(TZ).to_date.beginning_of_month)
      return nil unless goal.purchase? && goal.active?
      commitment = goal.savings_commitment
      return nil unless commitment&.paid_in?(month)
      sobra = MonthSummary.new(goal.account, month).remaining_cents
      return nil unless sobra.positive? && sobra * 5 >= goal.monthly_target_cents.to_i
      new(sobra_cents: sobra, source_bank_account_id: commitment.bank_account_id,
          destination_bank_account_id: goal.bank_account_id)
    end
  end
end
