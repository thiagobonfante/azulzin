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

  # What WE think this fatura amounts to: posted rows plus the live carryover estimate
  # (rows can never contain encargos, so a rotativo-carrying bill must be compared
  # against this, never against raw computed). Ignores stated on purpose — this is the
  # comparison baseline for the conferência.
  def our_total_cents
    computed_total_cents + (CardBills::Carryover.estimate(credit_card, billing_month)&.dig(:total_cents) || 0)
  end

  # A conferência is UNRESOLVED while the informed bank number disagrees with our figure.
  def divergence_pending? = stated_total_cents.present? && stated_total_cents != our_total_cents

  # THE closed-bill figure every surface shows: OUR figure (rows + carryover estimate —
  # a rotativo-carrying bill is never just its rows, founder round 2026-07-22b), replaced
  # by the bank's number only once a conferência RESOLVES. While pending the bank's
  # number does NOT replace ours anywhere — the user keeps seeing OUR total plus a
  # warning until the check concludes (move/adjust/cancel).
  def effective_total_cents
    divergence_pending? ? our_total_cents : (stated_total_cents || our_total_cents)
  end

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

  # Fully paid, but the last payment landed after the due date — the badge says so
  # ("paga em atraso") instead of pretending it was on time (founder ask, 2026-07-22).
  def paid_late?
    return false unless paid?
    (last = payments.posted.kept.maximum(:occurred_on)) ? last > due_on : false
  end

  # The unpaid remainder was carried into a NEWER closed bill (CardBills::Carryover), so
  # the debt lives there now — this bill must not keep reading "vencida" forever nor stay
  # the pay entry point (the newest bill is, carryover included).
  def rolled?
    !paid? && credit_card.card_bills.where("billing_month > ?", billing_month).exists?
  end

  # Status as the UI names it — overdue styling only after due_on (01 §4.1); paid-late and
  # rolled refine it so a settled or carried-forward bill never screams "vencida".
  def display_status
    if paid? then paid_late? ? "paid_late" : "paid"
    elsif rolled? then "rolled"
    elsif overdue? then "overdue"
    else status
    end
  end

  # What's left after the due date — feeds the rotativo projection (02 §5). Signed:
  # overpayment yields a NEGATIVE carryover (credit on the next bill), never clamped.
  def carryover_cents = effective_total_cents - paid_cents

  # Conferência action journal: informing a value starts a fresh log; moves and
  # adjustments append; cancel replays it BACKWARDS (founder rule 2026-07-22c — cancel
  # rolls back everything the review did). Added missing purchases are NOT logged: they
  # are real spending the user found, not review bookkeeping.
  def log_review!(entry) = update!(review_log: review_log + [ entry ])

  def rollback_review!
    review_log.reverse_each do |entry|
      case entry["kind"]
      when "move"
        entry["rows"].each do |r|
          credit_card.family_transactions.kept.find_by(id: r["id"])
                     &.update!(billing_month: billing_month, billing_month_manual: r["manual_was"])
        end
      when "adjust"
        credit_card.family_transactions.kept.find_by(id: entry["id"])&.soft_delete!
      end
    end
    update!(review_log: [], stated_total_cents: nil)
  end

  private
    def billing_month_is_first_of_month
      return if billing_month.blank? || billing_month == billing_month.beginning_of_month
      errors.add(:billing_month, :invalid)
    end
end
