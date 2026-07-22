class BankAccount < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable, SoftDeletable

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

  # Mirrors the hard-destroy restrict_with_error on incomes: an active income needs its deposit
  # account, so refuse the soft delete while one is kept (doc 05 §2.2).
  def soft_delete!(by: Current.user)
    if incomes.kept.exists?
      errors.add(:base, :has_kept_incomes)
      return false
    end
    super
  end

  # What to show as the account's title — a user nickname if given, else the bank name.
  def display_name = nickname.presence || institution.display_name

  def balance_informed? = balance_cents.present?

  # §7.1 derived balance ("now"): the anchored balance plus signed posted rows created after
  # the anchor. THE balance every screen shows — the stored balance_cents alone goes stale as
  # soon as a transaction posts. nil when the balance was never informed.
  #
  # as_of: the balance at the END of that date — rows that OCCURRED later are rewound.
  # Built once for the extrato drift headline (.plans/credit-cards 03 §2) and the
  # guardado-chart plan. Advisory by nature: the anchor is created_at-based while the
  # rewind is occurred_on-based, so a backdated future row reads approximately.
  def derived_balance_cents(as_of: nil)
    return nil unless balance_informed?
    since = balance_anchored_at || updated_at
    own = transactions.posted.kept.where("created_at > ?", since)   # .kept: a soft-deleted row unspends (doc 05)
    balance = balance_cents +
      own.where(direction: "income").sum(:amount_cents) -
      own.where(direction: %w[expense transfer]).sum(:amount_cents) +
      incoming_transfers.posted.kept.where("created_at > ?", since).sum(:amount_cents)
    return balance if as_of.nil?

    later = transactions.posted.kept.where("occurred_on > ?", as_of)
    balance -
      later.where(direction: "income").sum(:amount_cents) +
      later.where(direction: %w[expense transfer]).sum(:amount_cents) -
      incoming_transfers.posted.kept.where("occurred_on > ?", as_of).sum(:amount_cents)
  end

  private
    def stamp_balance_anchor
      self.balance_anchored_at = Time.current
    end
end
