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
end
