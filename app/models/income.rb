# A recurring income (salary, pension, …) — a schedule DEFINITION, never a materialized row.
# "Expected in month M" is computed via Recurrence; only real deposits (posted income-direction
# transactions linked by income_id) persist. See .plans/transactions/01-domain-model.md §5.
class Income < ApplicationRecord
  include MoneyColumns

  belongs_to :user
  belongs_to :bank_account
  has_many :receipts, class_name: "Transaction", foreign_key: :income_id, dependent: :nullify

  money_column :amount

  enum :schedule_kind, { fixed_day: "fixed_day", nth_business_day: "nth_business_day" }, validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :schedule_day, numericality: { only_integer: true, in: 1..31 }, if: :fixed_day?
  validates :schedule_day, numericality: { only_integer: true, in: 1..10 }, if: :nth_business_day?

  scope :active, -> { where(archived_at: nil) }

  # The date this income is expected in the given month (first-of-month Date).
  def expected_on(month) = Recurrence.date_for(schedule_kind, schedule_day, month)

  # Has a posted deposit for this income already landed in the month? (R1 counts-once, §7.3.)
  def received_in?(month) = receipts.posted.where(billing_month: month).exists?
end
