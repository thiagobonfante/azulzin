module Commitments
  # Early payoff ("quitar") of a debit installment plan: one posted transaction for the
  # negotiated payoff amount — billed to the next unpaid month, so it never collides with the
  # paid-once index — then the commitment is archived (occurrences stop, history is kept).
  class Settle
    def self.call(commitment, amount_cents)
      month = commitment.next_charge_month
      raise ArgumentError, "nothing left to settle" unless month
      txn = nil
      ActiveRecord::Base.transaction do
        txn = MarkPaid.call(commitment, month, amount: amount_cents)
        commitment.update!(archived_at: Time.current)
      end
      txn
    end
  end
end
