# A computed occurrence of a commitment in a given month (R10) — a plain value object, never
# a materialized row (occurrences are pure functions over the schedule + posted payments). The
# synthetic to_param keeps the PATCH /commitment_occurrences/:id/pay route working without a
# table. See .plans/transactions/05-commitments.md §5.2.
class CommitmentOccurrence
  attr_reader :commitment, :month

  # payment may be pre-injected in bulk (query 8) to avoid an N+1; :unset means "load lazily".
  def initialize(commitment, month, payment: :unset)
    @commitment = commitment
    @month      = month.beginning_of_month
    @payment    = payment
  end

  def to_param = "#{commitment.id}-#{month.strftime('%Y-%m')}"

  # Parse "42-2026-08" and authorize the commitment through the account's own kept set.
  def self.find_for!(account, param)
    id, year, mon = param.split("-")
    commitment = account.commitments.kept.find(id)
    new(commitment, Date.new(year.to_i, mon.to_i, 1))
  end

  # The month's occurrences across the account's active commitments — one payments query, no N+1.
  def self.for_month(account, month)
    month = month.beginning_of_month
    commitments = account.commitments.kept.active.includes(:bank_account, :credit_card, :category).to_a
                         .select { |c| c.active_in?(month) }
    payments = account.transactions.posted.kept
                      .where(commitment_id: commitments.map(&:id), billing_month: month).index_by(&:commitment_id)
    commitments.map { |c| new(c, month, payment: payments[c.id]) }
  end

  # A commitment's occurrence history for its show page, oldest first, over
  # [starts_on .. min(last occurrence, current + 12mo)] — one payments query.
  def self.history_for(commitment)
    first = commitment.starts_on.beginning_of_month
    last  = [ commitment.last_month&.beginning_of_month || (Date.current.beginning_of_month >> 12),
              Date.current.beginning_of_month >> 12 ].min
    payments = commitment.payments.posted.kept.index_by(&:billing_month)
    months, m = [], first
    while m <= last
      months << m
      m = m >> 1
    end
    # The 12-month horizon only trims unpaid future noise — a parcel PAID beyond it
    # (an advanced última) must still render in the paid history.
    months |= payments.keys.select { |mo| mo > last }.sort
    months.map { |mo| new(commitment, mo, payment: payments[mo]) }
  end

  def due_on = commitment.due_on(month)
  def installment_no = commitment.installment_no(month)
  def card? = commitment.credit_card_id.present?

  def payment
    return @payment unless @payment == :unset
    @payment = commitment.payments.posted.kept.find_by(billing_month: month)
  end

  # Historical presumption (§5.4): a month before the commitment's creation month with no
  # payment renders paid (presumed) — no backfilled transaction.
  def presumed_paid?
    payment.nil? && month < commitment.created_at.to_date.beginning_of_month
  end

  def paid? = payment.present? || presumed_paid?

  def status
    return :paid if paid?
    return :upcoming if due_on > Date.current
    due_on == Date.current ? :due_today : :overdue
  end
end
