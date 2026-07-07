module Commitments
  # Resizes an installment plan when the user fixes the parcel count on the edit form ("was
  # 36x, actually 38x"). Growing/shrinking never drops below min_installments_count (shrinking
  # to exactly it just ends the plan). Both card and debit parcels are computed occurrences, so a
  # resize only moves count/total — any parcels already marked paid survive as posted payments and
  # bound the floor via min_installments_count. Assigns without saving — the caller saves in the
  # same transaction.
  class AdjustCount
    def self.call(commitment, new_count)
      return true if new_count.blank? || !commitment.installment?
      count = new_count.to_i
      return true if count == commitment.installments_count
      if count < commitment.min_installments_count
        commitment.errors.add(:installments_count, :below_paid, count: commitment.min_installments_count)
        return false
      end
      commitment.total_cents = commitment.amount_cents * count
      commitment.installments_count = count
      true
    end
  end
end
