# A recurring obligation (R10) OR a card installment-purchase parent (R11). Four kinds:
#   installment  — finite: a car loan (debit) or a "5000 em 10x" card purchase. count present.
#   fixed        — a rent/school obligation with a known amount and (optional) end date.
#   subscription — Netflix etc.; charge day often unknown (schedule_day nil ⇒ end of month).
#   savings      — a monthly "pay yourself first" contribution (.plans/goals 07 §1). The
#                  bank_account is the SOURCE; paying it posts a transfer into the goal's caixinha
#                  (not an expense), so it reduces sobra via MonthSummary#projected_guardado_cents.
#                  Two modes: goal-linked purchase = finite parcelado (ends_on = last parcel month,
#                  parcels_count derived); goal-linked savings_rate or standalone = open-ended.
# Exactly one instrument (bank XOR card, DB-enforced). Occurrences are COMPUTED, never stored;
# a payment is an ordinary posted transaction linked by commitment_id. See 01-domain-model.md §5.
class Commitment < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable, SoftDeletable

  belongs_to :bank_account, optional: true
  belongs_to :credit_card,  optional: true
  belongs_to :category,     optional: true
  belongs_to :goal,         optional: true   # set only on kind: "savings" (.plans/goals 07 §1.2)
  has_many :payments, class_name: "Transaction", foreign_key: :commitment_id
  # Detach payments on destroy in ONE update: the DB pairs installment_number with commitment_id
  # (transactions_installment_requires_commitment), so dependent: :nullify — which clears only
  # the FK — would trip the check on any paid parcel (e.g. in the LGPD user cascade).
  before_destroy { payments.update_all(commitment_id: nil, installment_number: nil) }

  money_column :amount, :total

  enum :kind, { installment: "installment", fixed: "fixed", subscription: "subscription", savings: "savings" }, validate: true
  enum :schedule_kind, { fixed_day: "fixed_day", nth_business_day: "nth_business_day" }, validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :starts_on, presence: true
  validate  :exactly_one_instrument
  validate  :goal_only_on_savings   # goal_id is set only on the "pay yourself first" savings kind
  validate  :instrument_belongs_to_account   # tenancy backstop — a service may create! via params
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

  # Derived parcel total for the "N/total" display (round 3 decision 4). Installments carry it as
  # installments_count; a goal's savings commitment carries it as the starts_on..ends_on month span
  # (Goals::Activate sets ends_on = starts_on >> (n−1) — no schema change, the DB pairing of
  # installments_count with kind installment stands). nil = open-ended, no parcel UX.
  def parcels_count
    return installments_count if installment?
    return nil unless savings? && ends_on
    installment_no(ends_on.beginning_of_month)
  end

  # paid_count generalized across both parcelado shapes (presumed_paid_count is 0 for savings —
  # the commitment is created before its first occurrence).
  def paid_parcels_count
    (presumed_paid_count + posted_paid_count).clamp(0, parcels_count.to_i)
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

  # Floor when editing installments_count: what's already paid can't be dropped. Debit counts
  # presumed months + the furthest posted parcel (reverting a payment lowers it); card counts
  # parcels on closed bills — the open bill's parcels can still be resized away.
  def min_installments_count
    return 1 unless installment?
    floor =
      if card?
        payments.posted.kept.where(billing_month: ...credit_card.current_open_bill_month).maximum(:installment_number)
      else
        last_paid = payments.posted.kept.maximum(:billing_month)
        [ presumed_paid_count, last_paid ? installment_no(last_paid) : 0 ].max
      end
    [ floor.to_i, 1 ].max
  end

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

    def goal_only_on_savings
      errors.add(:goal, :only_on_savings) if goal_id.present? && !savings?
    end

    # A commitment's instrument must live in the same account (params-driven create! backstop).
    def instrument_belongs_to_account
      errors.add(:bank_account, :wrong_account) if bank_account && bank_account.account_id != account_id
      errors.add(:credit_card,  :wrong_account) if credit_card && credit_card.account_id != account_id
    end
end
