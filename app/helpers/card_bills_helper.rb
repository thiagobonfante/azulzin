module CardBillsHelper
  # display_status → daisyUI badge tone: blue family while open, error only past due.
  CARD_BILL_BADGE_CLASSES = {
    "paid"           => "badge-success",
    "partially_paid" => "badge-info",
    "unpaid"         => "badge-primary badge-outline",
    "overdue"        => "badge-error"
  }.freeze

  def card_bill_badge_class(bill)
    CARD_BILL_BADGE_CLASSES.fetch(bill.display_status, "badge-ghost")
  end

  # Where a reconciliation run's "back" lands: the bill page when the row exists;
  # bank runs go home to the accounts page.
  def back_link_for(import)
    return bank_accounts_path if import.bank_account_id
    bill = import.credit_card&.card_bills&.find_by(billing_month: import.period)
    bill ? card_bill_path(bill) : credit_cards_path
  end
end
