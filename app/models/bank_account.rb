class BankAccount < ApplicationRecord
  include MoneyColumns

  belongs_to :user
  belongs_to :institution                        # required (belongs_to is non-optional)
  has_many :transactions, dependent: :nullify    # deleting an account must not erase history

  money_column :balance

  validates :nickname,       length: { maximum: 80 }, allow_blank: true
  validates :agency,         length: { maximum: 20 }, allow_blank: true
  validates :account_number, length: { maximum: 30 }, allow_blank: true
  validates :balance_cents,  numericality: true, allow_nil: true

  # What to show as the account's title — a user nickname if given, else the bank name.
  def display_name = nickname.presence || institution.display_name

  def balance_informed? = balance_cents.present?
end
