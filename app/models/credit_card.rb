class CreditCard < ApplicationRecord
  include MoneyColumns

  belongs_to :user
  belongs_to :institution                        # required (belongs_to is non-optional)
  has_many :transactions, dependent: :nullify    # deleting a card must not erase history

  money_column :credit_limit, :current_bill

  # Digits-only last four (helps same-bank card disambiguation, e.g. "final 1234").
  normalizes :last4, with: ->(v) { v.to_s.gsub(/\D/, "").presence }

  validates :nickname,           length: { maximum: 80 }, allow_blank: true
  validates :last4,              format: { with: /\A\d{4}\z/ }, allow_nil: true
  validates :credit_limit_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :current_bill_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def display_name = nickname.presence || institution.display_name

  # A zero (or nil) limit counts as "not informed": a card with no usable credit renders
  # like an unknown-limit card instead of producing a nil usage_ratio the views divide on.
  def limit_informed? = credit_limit_cents.to_i.positive?

  # Available credit = limit − current bill (treats an unknown bill as 0). nil when the
  # limit itself is unknown/zero.
  def available_cents
    return nil unless limit_informed?
    credit_limit_cents - current_bill_cents.to_i
  end

  # Fraction of the limit used, clamped to 0..1 — drives the usage bar. Display-only, so
  # a float here never touches stored money. nil when the limit is unknown/zero.
  def usage_ratio
    return nil unless limit_informed?
    current_bill_cents.to_i.fdiv(credit_limit_cents).clamp(0.0, 1.0)
  end
end
