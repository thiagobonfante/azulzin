module Commitments
  # Pays several occurrences in one go ("paguei 3 parcelas de uma vez"): the negotiated total
  # is split evenly across the months — the first months absorb the leftover cents — one posted
  # payment each, so per-parcel history, progress and the paid-once index all keep working.
  class PayBatch
    def self.call(commitment, months, total_cents)
      months = months.map(&:beginning_of_month).uniq.sort
                     .select { |m| commitment.active_in?(m) && !commitment.paid_in?(m) }
      return [] if months.empty?
      base, leftover = total_cents.divmod(months.size)
      ActiveRecord::Base.transaction do
        months.each_with_index.map do |month, i|
          MarkPaid.call(commitment, month, amount: base + (i < leftover ? 1 : 0))
        end
      end
    end
  end
end
