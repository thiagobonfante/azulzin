module CardBills
  # Presentation-only carryover (.plans/credit-cards 02 §5): after an underpaid bill's due
  # date, the NEXT month's fatura surfaces gain two labeled lines — "veio da fatura de X"
  # and "encargos estimados" (one rotativo cycle at the BCB average). NEVER transaction
  # rows, never balance writes; everything here is derived live, so paying the old bill
  # (or accepting the new bill's stated_total) makes the lines vanish on their own.
  module Carryover
    module_function

    # The display lines. Pinned rule, refined 2026-07-22: a stated_total suppresses the
    # estimate only once it's AUTHORITATIVE (conferência resolved — the bank's encargos
    # are inside its number). While the check is pending, our estimate keeps showing.
    def for(card, month)
      bill = card.card_bills.find_by(billing_month: month)
      return nil if bill&.stated_total_cents && !bill.divergence_pending?
      estimate(card, month)
    end

    # → { from_month:, carryover_cents:, encargos_cents:, total_cents:, rate_month: } | nil
    # The raw estimate, ignoring any stated_total on `month` — CardBill#our_total_cents
    # compares the bank's number against THIS (rows alone can never contain encargos).
    # Overpayment carries NEGATIVE (a credit on the next bill) with zero encargos.
    def estimate(card, month)
      prev = card.card_bills.find_by(billing_month: month << 1)
      return nil unless prev && Date.current > prev.due_on

      carry = prev.carryover_cents
      return nil if carry.zero?

      rate = (BcbRate.current("rotativo") if carry.positive?)
      encargos = rate ? Rotativo.cycle_cost(carry, monthly_rate: rate.monthly_rate)[:total_cents] : 0
      { from_month: prev.billing_month, carryover_cents: carry, encargos_cents: encargos,
        total_cents: carry + encargos, rate_month: rate&.reference_month }
    end
  end
end
