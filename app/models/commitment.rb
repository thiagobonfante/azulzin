# A recurring obligation (R10) OR a card installment-purchase parent (R11). Three kinds:
#   installment  — finite: a car loan (debit) or a "5000 em 10x" card purchase. count present.
#   fixed        — a rent/school obligation with a known amount and (optional) end date.
#   subscription — Netflix etc.; charge day often unknown (schedule_day nil ⇒ end of month).
# Exactly one instrument (bank XOR card, DB-enforced). Occurrences are COMPUTED, never stored;
# a payment is an ordinary posted transaction linked by commitment_id. See 01-domain-model.md §5.
class Commitment < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable, SoftDeletable

  belongs_to :bank_account, optional: true
  belongs_to :credit_card,  optional: true
  belongs_to :category,     optional: true
  has_many :payments, class_name: "Transaction", foreign_key: :commitment_id
  # Detach payments on destroy in ONE update: the DB pairs installment_number with commitment_id
  # (transactions_installment_requires_commitment), so dependent: :nullify — which clears only
  # the FK — would trip the check on any paid parcel (e.g. in the LGPD user cascade).
  before_destroy { payments.update_all(commitment_id: nil, installment_number: nil) }

  money_column :amount, :total

  enum :kind, { installment: "installment", fixed: "fixed", subscription: "subscription" }, validate: true
  enum :schedule_kind, { fixed_day: "fixed_day", nth_business_day: "nth_business_day" }, validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :starts_on, presence: true
  validate  :exactly_one_instrument
  validates :installments_count, numericality: { only_integer: true, greater_than: 0 }, if: :installment?
  validates :installments_count, absence: true, unless: :installment?
  validates :schedule_day, presence: true, if: :fixed?   # subscription: unknown; installment: posted parcels
  validates :schedule_day, numericality: { only_integer: true, in: 1..31 }, if: -> { fixed_day? && schedule_day.present? }
  validates :schedule_day, numericality: { only_integer: true, in: 1..10 }, if: -> { nth_business_day? && schedule_day.present? }

  scope :active, -> { where(archived_at: nil) }

  # Last month this commitment has an occurrence: derived for installments, ends_on for fixed,
  # nil (open-ended) for subscriptions and end-less fixed.
  def last_month
    installment? ? (starts_on >> (installments_count - 1)) : ends_on
  end

  # Is there an occurrence in month M (first-of-month Date)?
  def active_in?(month)
    return false if month < starts_on.beginning_of_month
    lm = last_month
    lm.nil? || month <= lm.beginning_of_month
  end

  # The date the occurrence is due in month M (nil schedule_day ⇒ end of month, display-only).
  def due_on(month)
    return month.end_of_month if schedule_day.blank?
    Recurrence.date_for(schedule_kind, schedule_day, month)
  end

  # Has a posted payment for M been recorded? (Unique per (commitment, billing_month), §3.)
  def paid_in?(month) = payments.posted.kept.where(billing_month: month).exists?

  # The next month with an unpaid occurrence, from `from` (default: this month) — a paid
  # current parcel advances "Próximo" to the following one. nil when none remain.
  def next_charge_month(from = Date.current.beginning_of_month)
    month = [ from.beginning_of_month, starts_on.beginning_of_month ].max
    month = month >> 1 while active_in?(month) && paid_in?(month)
    active_in?(month) ? month : nil
  end

  # "parcela N/total" — months since starts_on + 1.
  def installment_no(month)
    (month.year * 12 + month.month) - (starts_on.year * 12 + starts_on.month) + 1
  end

  def archived? = archived_at.present?
  def card? = credit_card_id.present?
  def instrument = credit_card || bank_account

  # Occurrences before this commitment existed count as presumed-paid (mid-plan onboarding §5.4).
  def presumed_paid_count
    return 0 unless installment?
    created_month = (created_at || Time.current).to_date.beginning_of_month
    months = (created_month.year * 12 + created_month.month) - (starts_on.year * 12 + starts_on.month)
    months.clamp(0, installments_count)
  end

  def posted_paid_count = payments.posted.kept.count

  # For the progress bar "%{paid} de %{count} pagas".
  def paid_count
    (presumed_paid_count + posted_paid_count).clamp(0, installments_count.to_i)
  end

  # "Faltam %{amount}" = total − (presumed months + posted payments/parcels).
  def remaining_cents
    return nil unless installment? && total_cents
    paid_value = presumed_paid_count * amount_cents + payments.posted.kept.sum(:amount_cents)
    [ total_cents - paid_value, 0 ].max
  end

  private
    # Mirror of the DB check "num_nonnulls(bank_account_id, credit_card_id) = 1" for friendly errors.
    def exactly_one_instrument
      return if bank_account_id.present? ^ credit_card_id.present?
      errors.add(:base, :one_instrument)
    end
end
