# A money movement captured from WhatsApp (or entered manually). The single source of
# truth for spend — in v1 it is a PURE RECORD: posting does NOT mutate the stored
# bank_account/credit_card balances (that removes the drift/double-count/undo class of
# bugs; balance reconciliation is a later phase). See .plans/whats (Review P0-3).
#
# Note: this model is named Transaction, which shadows ActiveRecord's `transaction`
# helper on *associations* — call ActiveRecord::Base.transaction explicitly for DB txns.
class Transaction < ApplicationRecord
  include MoneyColumns

  belongs_to :user
  belongs_to :bank_account, optional: true
  belongs_to :credit_card,  optional: true
  belongs_to :whatsapp_message, optional: true, inverse_of: :produced_transactions   # the inbound msg that produced it

  # Outbound reply messages about this transaction (audit trail). nullify so destroying a
  # transaction never orphans/violates the whatsapp_messages.transaction_id FK.
  has_many :reply_messages, class_name: "WhatsappMessage",
           foreign_key: :transaction_id, dependent: :nullify, inverse_of: :linked_transaction

  money_column :amount

  # string-backed enums (readable in the DB, give scopes). New pattern for this codebase.
  enum :direction, { expense: "expense", income: "income", transfer: "transfer" },
       default: "expense", validate: true

  enum :status, {
    posted:               "posted",
    needs_confirmation:   "needs_confirmation",
    needs_clarification:  "needs_clarification",
    needs_disambiguation: "needs_disambiguation",
    pending_review:       "pending_review",
    rejected:             "rejected",
    superseded:           "superseded"
  }, default: "pending_review", validate: true

  OPEN_ASK_STATUSES = %w[needs_confirmation needs_clarification needs_disambiguation].freeze

  validates :amount_cents, numericality: { only_integer: true }
  validates :occurred_on, presence: true
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true

  scope :spend, -> { posted.where(direction: "expense") }        # excludes rejected/superseded
  scope :unassigned, -> { where(bank_account_id: nil, credit_card_id: nil) }
  scope :in_app_inbox, -> { where(status: %w[pending_review needs_confirmation needs_clarification needs_disambiguation]) }

  # The single outstanding confirm/clarify question for a user (one open ask per user).
  # The next inbound reply is routed to this. See .plans/whats §5.1.
  def self.open_ask_for(user)
    where(user: user, status: OPEN_ASK_STATUSES)
      .where("ask_expires_at > ?", Time.current)
      .order(created_at: :desc).first
  end

  # The instrument an expense is charged to (nil ⇒ unassigned; assign in-app).
  def instrument = bank_account || credit_card
  def assigned?  = instrument.present?
end
