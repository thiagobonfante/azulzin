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

  # Statuses that keep a row in the in-app pending inbox (open/pending asks). The inbox ALSO
  # surfaces posted-but-unassigned rows — see #in_pending_inbox? and the pending_inbox scope.
  PENDING_INBOX_STATUSES = (OPEN_ASK_STATUSES + %w[pending_review]).freeze

  validates :amount_cents, numericality: { only_integer: true }
  validates :occurred_on, presence: true
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true

  scope :spend, -> { posted.where(direction: "expense") }        # excludes rejected/superseded
  scope :unassigned, -> { where(bank_account_id: nil, credit_card_id: nil) }
  scope :in_app_inbox, -> { where(status: %w[pending_review needs_confirmation needs_clarification needs_disambiguation]) }

  # The in-app pending inbox (.plans/whats §5.8): open/pending asks PLUS posted expenses with
  # no instrument yet (auto-committed, waiting for the user to pick an account in-app).
  scope :pending_inbox, lambda {
    where("status IN (:pending) OR (status = 'posted' AND bank_account_id IS NULL AND credit_card_id IS NULL)",
          pending: PENDING_INBOX_STATUSES)
  }

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

  # Does this row still belong in the pending inbox? Drives whether an in-app action replaces
  # the row (still pending) or removes it (resolved). Mirrors the pending_inbox scope.
  def in_pending_inbox? = PENDING_INBOX_STATUSES.include?(status) || (posted? && !assigned?)

  # Minimum match strength to auto-assign an instrument on a silent post; below this we
  # post UNASSIGNED (never guess the account) and let the user assign in-app.
  MATCH_ASSIGN_MIN = 0.70

  # Guarded conditional transition: only applies `attrs` if the row is still in one of
  # `from_statuses`, and returns whether it moved. Prevents the confirm-vs-expiry and
  # confirm-vs-supersede races (Review P1-3) — a late reply can't commit a row the sweep
  # already expired. Uses update_all (no callbacks) so it is a single atomic UPDATE.
  def guarded_update(from_statuses, attrs)
    n = self.class.where(id: id, status: from_statuses)
             .update_all(attrs.merge(updated_at: Time.current))
    reload if n.positive?
    n.positive?
  end

  # Reverse a posted transaction (the in-app / "apagar" undo). Excluded from spend once
  # rejected. Pure record ⇒ nothing to un-bump.
  def reverse! = update!(status: "rejected")

  # Assign (or reassign) the instrument in-app; clears the other side.
  def assign_instrument!(record)
    case record
    when BankAccount then update!(bank_account: record, credit_card: nil)
    when CreditCard  then update!(credit_card: record, bank_account: nil)
    else raise ArgumentError, "not an instrument: #{record.class}"
    end
  end
end
