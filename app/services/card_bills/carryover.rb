module CardBills
  # Presentation-only carryover (.plans/credit-cards 02 §5): after an underpaid bill's due
  # date, the NEXT month's fatura surfaces gain two labeled lines — "veio da fatura de X"
  # and "encargos estimados" (one rotativo cycle at the BCB average). NEVER transaction
  # rows, never balance writes; everything here is derived live, so paying the old bill
  # (or informing the new bill's stated_total) makes the lines vanish on their own.
  module Carryover
    module_function

    # → { from_month:, carryover_cents:, encargos_cents:, total_cents:, rate_month: } | nil
    # Overpayment carries NEGATIVE (a credit on the next bill) with zero encargos.
    def for(card, month)
      prev = card.card_bills.find_by(billing_month: month << 1)
      return nil unless prev && Date.current > prev.due_on
      # Pinned rule: estimates never coexist with a stated_total on the same bill —
      # once the bank's number is in, its encargos are inside it.
      return nil if card.card_bills.find_by(billing_month: month)&.stated_total_cents

      carry = prev.carryover_cents
      return nil if carry.zero?

      rate = (BcbRate.current("rotativo") if carry.positive?)
      encargos = rate ? Rotativo.cycle_cost(carry, monthly_rate: rate.monthly_rate)[:total_cents] : 0
      { from_month: prev.billing_month, carryover_cents: carry, encargos_cents: encargos,
        total_cents: carry + encargos, rate_month: rate&.reference_month }
    end
  end
end
