# A contracted "parcelamento de fatura" on a closed bill (.plans/credit-cards, founder
# 2026-07-22d): the user paid an entrada (a normal Pay transfer) and the bank split the
# remainder into N fixed parcels landing on the next faturas. The BANK's numbers rule —
# parcela and count come from the bank's app, never computed. Parcels are derived lines
# via CreditCard#bill_cents (the Carryover spine: never transaction rows, never balance
# writes), so destroying this row is the rollback: plain carryover behavior returns.
class CardBillFinancing < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable

  belongs_to :card_bill
  # The entrada payment the financing form posted (nil when it was recorded via Pagar
  # beforehand, or hard-deleted) — cancel reverses it along with the plan.
  belongs_to :down_payment_transaction, class_name: "Transaction", optional: true

  money_column :installment, :financed

  validates :installments_count, numericality: { only_integer: true, in: 2..48 }
  validates :installment_cents,  numericality: { only_integer: true, greater_than: 0 }
  validates :financed_cents,     numericality: { only_integer: true, greater_than: 0 }
  validates :first_charge_month, presence: true
  validate  :first_charge_after_bill
  validate  :parcels_cover_principal   # parcela × count < financed would mean negative juros

  # Everything the plan will collect, and the juros+IOF baked into it.
  def total_cents          = installment_cents * installments_count
  def finance_charges_total_cents = total_cents - financed_cents

  def last_charge_month = first_charge_month >> (installments_count - 1)

  def active_in?(month)
    month >= first_charge_month && month <= last_charge_month
  end

  # "parcela N/count" for a billing month inside the schedule.
  def parcel_no(month)
    (month.year * 12 + month.month) - (first_charge_month.year * 12 + first_charge_month.month) + 1
  end

  # The juros+IOF share of parcel N — even split, remainder cents on parcel 1.
  # ponytail: even split, not the Price front-loaded curve — totals are exact and the
  # per-month drift is centavos; swap in a solved-rate Price split if anyone ever cares.
  def finance_charges_for(parcel_no)
    base = finance_charges_total_cents / installments_count
    parcel_no == 1 ? base + finance_charges_total_cents % installments_count : base
  end

  # Principal still held against the card limit: banks keep the parceled amount consuming
  # limit and release it as parcels are paid. Proportional to parcels not yet billed
  # (a parcel on the open bill or later is unpaid by construction — it's paid by paying
  # that future fatura).
  def held_cents(from_month)
    remaining = [ (last_charge_month.year * 12 + last_charge_month.month) -
                  (from_month.year * 12 + from_month.month) + 1, 0 ].max
    financed_cents * [ remaining, installments_count ].min / installments_count
  end

  private
    def first_charge_after_bill
      return if first_charge_month.blank? || card_bill.nil?
      errors.add(:first_charge_month, :invalid) unless
        first_charge_month == first_charge_month.beginning_of_month &&
        first_charge_month > card_bill.billing_month
    end

    def parcels_cover_principal
      return if installment_cents.blank? || installments_count.blank? || financed_cents.blank?
      errors.add(:installment_cents, :below_principal) if total_cents < financed_cents
    end
end
