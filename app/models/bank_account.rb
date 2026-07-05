class BankAccount < ApplicationRecord
  include MoneyColumns

  belongs_to :user
  belongs_to :institution                        # required (belongs_to is non-optional)
  has_many :transactions, dependent: :nullify    # deleting an account must not erase history
  has_many :incomes, dependent: :restrict_with_error   # an income needs its account; reassign before delete
  has_many :incoming_transfers, class_name: "Transaction",
           foreign_key: :transfer_to_bank_account_id, dependent: :nullify

  money_column :balance

  enum :kind, { checking: "checking", savings: "savings", investment: "investment" }, default: "checking", validate: true
  # checking / savings / investment scopes come free from the enum.

  validates :nickname,       length: { maximum: 80 }, allow_blank: true
  validates :agency,         length: { maximum: 20 }, allow_blank: true
  validates :account_number, length: { maximum: 30 }, allow_blank: true
  validates :balance_cents,  numericality: true, allow_nil: true

  # Editing the balance stamps "the balance was X at wall-clock time T"; derived balances add
  # signed posted rows created after the anchor (see MonthSummary §7.1).
  before_save :stamp_balance_anchor, if: :will_save_change_to_balance_cents?

  # What to show as the account's title — a user nickname if given, else the bank name.
  def display_name = nickname.presence || institution.display_name

  def balance_informed? = balance_cents.present?

  private
    def stamp_balance_anchor
      self.balance_anchored_at = Time.current
    end
end
