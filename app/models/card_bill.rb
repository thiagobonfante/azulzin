# A closed fatura (.plans/credit-cards 01). Materialized by CardBills::CloseScan the
# morning after closing; the OPEN bill stays a pure query (CreditCard#bill_cents). Stores
# only close-time snapshots (closed_on/due_on — settled history a config edit never
# rewrites) and the bank's own numbers as the user informs them. Everything else —
# computed total, paid, status — is derived live, so a late-arriving capture or an unpay
# can never contradict a stored copy. No soft delete: a bill is derived history with two
# annotations; a soft-deleted card simply stops rendering its bills.
class CardBill < ApplicationRecord
  include AccountScoped, Attributable

  belongs_to :credit_card
  # Payment transfers linked via transactions.card_bill_id (the commitment_id idiom).
  # Unscoped: paid_cents applies posted.kept itself; unpay needs to find any linked row.
  has_many :payments, class_name: "Transaction", foreign_key: :card_bill_id,
           dependent: :nullify, inverse_of: :card_bill

  validates :billing_month, :closed_on, :due_on, presence: true
  validates :stated_total_cents, :stated_minimum_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate  :billing_month_is_first_of_month

  # Live, so a late capture with a pre-closing occurred_on still lands here (expected
  # drift — one of the reasons the bank's number differs; phase 2 handles it).
  def computed_total_cents = credit_card.bill_cents(billing_month)

  # THE closed-bill figure every surface shows: the bank's number when informed, ours
  # otherwise (same one-figure discipline as bill_cents).
  def effective_total_cents = stated_total_cents || computed_total_cents

  def paid_cents = payments.posted.kept.sum(:amount_cents)

  # Derived, never stored — a stored status could contradict its own inputs after unpay.
  def status
    paid = paid_cents
    if paid <= 0 then "unpaid"
    elsif paid >= effective_total_cents then "paid"
    else "partially_paid"
    end
  end

  def paid?    = status == "paid"
  def overdue? = !paid? && due_on < Date.current

  # Status as the UI names it — overdue styling only after due_on (01 §4.1).
  def display_status = overdue? ? "overdue" : status

  # What's left after the due date — feeds the rotativo projection (02 §5). Signed:
  # overpayment yields a NEGATIVE carryover (credit on the next bill), never clamped.
  def carryover_cents = effective_total_cents - paid_cents

  private
    def billing_month_is_first_of_month
      return if billing_month.blank? || billing_month == billing_month.beginning_of_month
      errors.add(:billing_month, :invalid)
    end
end
