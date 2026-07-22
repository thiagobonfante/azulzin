class CreditCard < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable, SoftDeletable

  belongs_to :institution                        # required (belongs_to is non-optional)
  has_many :transactions, dependent: :nullify    # deleting a card must not erase history
  has_many :commitments,  dependent: :nullify    # card-charged subscriptions / installment plans (R10/R11)
  has_many :card_bills                           # closed faturas; stop rendering with a soft-deleted card

  # Sub-cards (.plans/credit-cards 04): one nullable self-FK, ONE level deep. A sub-card
  # (virtual copy / family adicional) carries no billing config and no limit — the cycle
  # and the limit belong to the root; its rows roll up into the root's bill.
  belongs_to :parent_card, class_name: "CreditCard", optional: true
  has_many :children, class_name: "CreditCard", foreign_key: :parent_card_id, inverse_of: :parent_card

  scope :roots, -> { where(parent_card_id: nil) }

  money_column :credit_limit, :current_bill

  enum :card_type, { physical: "physical", virtual: "virtual" }, default: "physical", validate: true
  # physical / virtual scopes come free from the enum.

  # Digits-only last four (helps same-bank card disambiguation, e.g. "final 1234").
  normalizes :last4, with: ->(v) { v.to_s.gsub(/\D/, "").presence }

  validates :nickname,           length: { maximum: 80 }, allow_blank: true
  validates :last4,              format: { with: /\A\d{4}\z/ }, allow_nil: true
  validates :credit_limit_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :current_bill_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # vencimento (nullable — unconfigured cards are legitimate); fechamento offset NOT NULL DEFAULT 7.
  validates :bill_due_day, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validates :closing_offset_days, numericality: { only_integer: true, in: 0..28 }
  validate :sub_card_shape, if: :parent_card_id?

  # Billing is configured once a vencimento is set (09 P0 #5 — keyed on bill_due_day alone).
  # A sub-card delegates to its root — the cycle belongs to the plastic that gets billed.
  def billing_configured? = billing_root.bill_due_day.present?

  def root?        = parent_card_id.nil?
  def sub_card?    = parent_card_id.present?
  def billing_root = parent_card || self
  def family_ids   = [ id, *children.kept.ids ]

  # The bill (fatura) a purchase on `date` lands on. THE single public call site for the R2
  # closing rule (09 P0 #3); the Billing module holds the algorithm. due_date/closing_date are
  # the same month math, exposed for the bill-detail view. Sub-card purchases bucket by the
  # ROOT's cycle (04 §2) — delegation here covers every write site at once.
  def billing_month_for(date) = Billing.billing_month_for(billing_root, date)
  def due_date(month)         = Billing.due_date(billing_root, month)
  def closing_date(month)     = Billing.closing_date(billing_root, month)

  def display_name = nickname.presence || institution.display_name

  # A zero (or nil) limit counts as "not informed": a card with no usable credit renders
  # like an unknown-limit card instead of producing a nil usage_ratio the views divide on.
  def limit_informed? = credit_limit_cents.to_i.positive?

  # The open (current) bill's month for this card.
  def current_open_bill_month = billing_month_for(Date.current)

  # Every bill/limit aggregate reads the FAMILY (root + kept sub-cards) — changed in
  # exactly one place each (04 §2); the count-once invariant is pinned in SUB-01.
  def family_transactions = Transaction.where(credit_card_id: family_ids)

  # Posted fatura component for a month: expenses − refunds (an income row on a card = estorno).
  def bill_total_cents(month)
    scope = family_transactions.posted.kept.where(billing_month: month)
    scope.where(direction: "expense").sum(:amount_cents) - scope.where(direction: "income").sum(:amount_cents)
  end

  # Hub-facing bill figure: posted rows PLUS card-commitment occurrences active in M with no
  # linked posted charge (05 §5.7). Constant before/after a subscription charge is linked.
  def bill_cents(month)
    bill_total_cents(month) + unlinked_card_commitment_cents(month)
  end

  # Committed-not-yet-paid usage (02 §6): a 10× purchase holds the FULL amount against the
  # limit immediately. Σ posted expenses on the open bill and later − same-range refunds,
  # PLUS commitment occurrences with no posted charge yet (see #reserved_commitment_cents) —
  # an imported mid-plan parcelamento or an upcoming assinatura holds limit before it posts.
  # Unconfigured cards fall back to the manual current_bill snapshot.
  def used_cents
    return current_bill_cents.to_i unless billing_configured?
    scope = family_transactions.posted.kept.where("billing_month >= ?", current_open_bill_month)
    scope.where(direction: "expense").sum(:amount_cents) -
      scope.where(direction: "income").sum(:amount_cents) +
      reserved_commitment_cents
  end

  # The open (current) bill figure the dashboard shows: composed (posted + unlinked
  # commitment projection) when billing is configured, else the manual snapshot.
  def open_bill_cents
    return current_bill_cents.to_i unless billing_configured?
    bill_cents(current_open_bill_month)
  end

  # Available credit = limit − committed usage. nil when the limit itself is unknown/zero.
  def available_cents
    return nil unless limit_informed?
    credit_limit_cents - used_cents
  end

  # Fraction of the limit used, clamped to 0..1 — drives the usage bar. Display-only.
  def usage_ratio
    return nil unless limit_informed?
    used_cents.fdiv(credit_limit_cents).clamp(0.0, 1.0)
  end

  # Recompute billing_month for this card's non-manual rows after a billing-config change.
  # (a) first_time (bill_due_day nil → set): recompute ALL non-manual rows — full-history
  # backfill. (b) subsequent: only the open bill and later — closed faturas stay settled.
  # Parcel-aware: parcel k lands k−1 months after parcel 1, so the fan-out is preserved.
  # A config change on the root re-buckets the CHILDREN's rows too (04 §2).
  def recompute_billing_months!(first_time:)
    scope = family_transactions.where(billing_month_manual: false)
    scope = scope.where(billing_month: current_open_bill_month..) unless first_time
    scope.find_each do |txn|
      m = billing_month_for(txn.occurred_on)
      m = m >> (txn.installment_number - 1) if txn.installment_number
      txn.update_column(:billing_month, m)
    end
  end

  # Orphan sub-cards are meaningless: removing a root with kept children is refused with a
  # friendly error; removing a sub-card is the existing nullify behavior (its rows keep
  # counting in the root's closed history via billing_month).
  def soft_delete!(by: Current.user)
    if root? && children.kept.exists?
      errors.add(:base, :has_kept_children)
      return false
    end
    super
  end

  private
    # Sub-card discipline (04 §1): one level only, same account + institution (a Nubank
    # virtual IS a Nubank card), and no own billing/limit — those belong to the root.
    def sub_card_shape
      errors.add(:parent_card, :nested)        if parent_card&.parent_card_id.present?
      errors.add(:parent_card, :cross_account) if parent_card && parent_card.account_id != account_id
      errors.add(:institution, :mismatch)      if parent_card && parent_card.institution_id != institution_id
      errors.add(:bill_due_day, :sub_card)     if bill_due_day.present?
      errors.add(:credit_limit_cents, :sub_card) if credit_limit_cents.present?
    end

    # Card-instrument commitments active in M without a linked posted charge. Zero until R10/R11
    # ship card commitments (Phase 4); the composition is defined here so bill_cents is stable.
    # Family-wide: a subscription riding a sub-card projects into the ROOT's bill.
    def unlinked_card_commitment_cents(month)
      Commitment.where(credit_card_id: family_ids).kept.active
                .select { |c| c.active_in?(month) && !c.paid_in?(month) }.sum(&:amount_cents)
    end

    # Committed-but-unposted usage from the open bill forward: every remaining unpaid parcel
    # of an installment plan (the whole remainder holds limit, like the fan-out would), and
    # the open bill's occurrence of a subscription/fixed (reserved until the charge posts).
    # Fan-out parcels exist as posted linked payments, so their months read paid — never
    # counted twice.
    def reserved_commitment_cents
      from = current_open_bill_month
      Commitment.where(credit_card_id: family_ids).kept.active
                .sum { |c| unposted_occurrence_months(c, from).size * c.amount_cents }
    end

    def unposted_occurrence_months(commitment, from)
      to = commitment.installment? ? commitment.last_month&.beginning_of_month : from
      return [] if to.nil? || to < from
      paid = commitment.payments.posted.kept.where(billing_month: from..).pluck(:billing_month).to_set
      months, m = [], from
      while m <= to
        months << m if commitment.active_in?(m) && !paid.include?(m)
        m = m >> 1
      end
      months
    end
end
