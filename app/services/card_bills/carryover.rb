module CardBills
  # Presentation-only carryover (.plans/credit-cards 02 §5): after an underpaid bill's due
  # date, the NEXT month's fatura surfaces gain two labeled lines — "veio da fatura de X"
  # and "encargos estimados" (one rotativo cycle at the BCB average). NEVER transaction
  # rows, never balance writes; everything here is derived live, so paying the old bill
  # (or accepting the new bill's stated_total) makes the lines vanish on their own.
  module Carryover
    module_function

    # → { from_month:, carryover_cents:, finance_charges_cents:, total_cents:, rate_month: } | nil
    # These ARE the display lines too — always shown as the figure's breakdown, even
    # after a stated_total is accepted (founder rule 2026-07-22c: resolving equalizes
    # our figure with the bank's, so the lines keep summing to the total).
    # The raw estimate, ignoring any stated_total on `month` — CardBill#our_total_cents
    # compares the bank's number against THIS (rows alone can never contain encargos).
    # Overpayment carries NEGATIVE (a credit on the next bill) with zero encargos.
    def estimate(card, month)
      prev = card.card_bills.find_by(billing_month: month << 1)
      return nil unless prev && Date.current > prev.due_on
      # A contracted parcelamento replaces the rotativo: the remainder rides the future
      # bills as parcel lines (CreditCard#financing_parcels_cents), never as carryover.
      return nil if prev.financed?

      carry = prev.carryover_cents
      return nil if carry.zero?

      rate = (BcbRate.current("rotativo") if carry.positive?)
      finance_charges = rate ? RevolvingCredit.cycle_cost(carry, monthly_rate: rate.monthly_rate)[:total_cents] : 0
      { from_month: prev.billing_month, carryover_cents: carry, finance_charges_cents: finance_charges,
        total_cents: carry + finance_charges, rate_month: rate&.reference_month }
    end
  end
end
