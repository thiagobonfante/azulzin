# Credit-card billing-cycle date math (R2 + R11). Pure Date arithmetic — no I/O, no
# Time.current. The single public entry point across the app is CreditCard#billing_month_for,
# which delegates here (09 P0 #3); due_date / closing_date are exposed for the bill-detail view.
# module_function, like Money. See .plans/transactions/02-credit-card-billing.md §3.
module Billing
  module_function

  # Due date of the bill named by billing_month (a first-of-month date). Clamp handles short
  # months: bill_due_day 31 in Feb → Feb 28/29.
  def due_date(card, billing_month)
    Date.new(billing_month.year, billing_month.month,
             [ card.bill_due_day, billing_month.end_of_month.day ].min)
  end

  # Plain Date subtraction — crosses month boundaries exactly (may land in the prior month).
  def closing_date(card, billing_month)
    due_date(card, billing_month) - card.closing_offset_days
  end

  # THE RULE: a purchase belongs to the EARLIEST bill whose closing date it does not exceed. A
  # purchase ON the closing date stays on that bill; the first day that rolls to the next bill
  # is closing_date + 1 (= "melhor dia de compra"). Unconfigured card ⇒ calendar month.
  def billing_month_for(card, occurred_on)
    return occurred_on.beginning_of_month unless card.billing_configured?
    m = occurred_on.beginning_of_month
    m = m.next_month while occurred_on > closing_date(card, m)
    m
  end
end
