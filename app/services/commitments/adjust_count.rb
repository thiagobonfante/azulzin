module Commitments
  # Resizes an installment plan when the user fixes the parcel count on the edit form ("was
  # 36x, actually 38x"). Growing appends parcels; shrinking drops the tail — never below
  # min_installments_count (shrinking to exactly it just ends the plan). Card plans (R11) have
  # real posted parcels riding future bills: appended ones follow at the current parcel amount,
  # dropped ones are soft-deleted. Debit occurrences are computed, so only count/total change.
  # Assigns the commitment without saving — the caller saves in the same transaction.
  class AdjustCount
    def self.call(commitment, new_count, by:)
      return true if new_count.blank? || !commitment.installment?
      count = new_count.to_i
      return true if count == commitment.installments_count
      if count < commitment.min_installments_count
        commitment.errors.add(:installments_count, :below_paid, count: commitment.min_installments_count)
        return false
      end
      if commitment.card?
        resize_card_parcels(commitment, count, by)
      else
        commitment.total_cents = commitment.amount_cents * count
      end
      commitment.installments_count = count
      true
    end

    def self.resize_card_parcels(commitment, count, by)
      parcels = commitment.payments.posted.kept.order(:installment_number).to_a
      dropped, kept = parcels.partition { |p| p.installment_number > count }
      dropped.each { |p| p.soft_delete!(by: by) }
      template = kept.last
      ((template&.installment_number || 0) + 1).upto(count) do |i|
        kept << commitment.account.transactions.create!(
          created_by: by, commitment: commitment, credit_card: commitment.credit_card,
          direction: "expense", status: "posted", payment_method: "credito",
          confirmed_at: Time.current, amount_cents: commitment.amount_cents,
          occurred_on: template&.occurred_on || commitment.starts_on,
          merchant: commitment.name, installment_number: i,
          billing_month: commitment.starts_on >> (i - 1), billing_month_manual: false,
          category_id: commitment.category_id)
      end
      commitment.total_cents = kept.sum(&:amount_cents)
    end
  end
end
