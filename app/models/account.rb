# The tenant (spine D1). One household's shared pool of financial data. Up to 4 members,
# exactly one owner. Not to be confused with BankAccount — "account" here means tenant.
class Account < ApplicationRecord
  MAX_MEMBERS = 4

  has_many :memberships, class_name: "AccountMembership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy                       # doc 02

  # LGPD hard-destroy cascade MOVES HERE from User (same ordering rationale as the old
  # user.rb comment: commitments/incomes reference accounts/cards/categories with NO-ACTION
  # FKs — and incomes restrict_with_error on their account — so destroy them first).
  has_many :goals,             dependent: :destroy                 # .plans/goals — nullifies its commitments/caixinha
  has_many :goal_checks,       dependent: :destroy
  has_many :commitments,       dependent: :destroy
  has_many :incomes,           dependent: :destroy
  has_many :categories,        dependent: :destroy
  has_many :bank_accounts,     dependent: :destroy
  has_many :credit_cards,      dependent: :destroy
  has_many :transactions,      dependent: :destroy
  has_many :whatsapp_messages, dependent: :destroy                 # account-owned audit trail
  has_many :document_imports,  dependent: :destroy
  has_many :notifications,     dependent: :destroy                 # alerts about this account's data

  validates :name, presence: true, length: { maximum: 120 }

  def owner = memberships.find_by(role: "owner")&.user

  # Race-safe join: the row lock serializes concurrent accepts; the members_count CHECK
  # constraint is the DB backstop for any path that skips this method.
  def add_member!(user, role: "member")
    with_lock { memberships.create!(user: user, role: role) }
  end
end
