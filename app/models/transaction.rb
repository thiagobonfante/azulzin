# A money movement captured from WhatsApp (or entered manually). The single source of
# truth for spend — in v1 it is a PURE RECORD: posting does NOT mutate the stored
# bank_account/credit_card balances (that removes the drift/double-count/undo class of
# bugs; balance reconciliation is a later phase). See .plans/whats (Review P0-3).
#
# Note: this model is named Transaction, which shadows ActiveRecord's `transaction`
# helper on *associations* — call ActiveRecord::Base.transaction explicitly for DB txns.
class Transaction < ApplicationRecord
  include MoneyColumns
  include AccountScoped    # belongs_to :account (spine D2)
  include Attributable     # created_by / updated_by (spine D7)
  include SoftDeletable    # deleted_at / .kept (spine D8)

  belongs_to :bank_account, optional: true
  belongs_to :credit_card,  optional: true
  belongs_to :category,     optional: true                                           # R6
  belongs_to :commitment,   optional: true                                           # R10/R11 payment/parcel link
  belongs_to :income,       optional: true                                           # R1 receipt link
  belongs_to :transfer_to_bank_account, class_name: "BankAccount", optional: true    # R5 destination leg
  belongs_to :whatsapp_message, optional: true, inverse_of: :produced_transactions   # the inbound msg that produced it

  # Outbound reply messages about this transaction (audit trail). nullify so destroying a
  # transaction never orphans/violates the whatsapp_messages.transaction_id FK.
  has_many :reply_messages, class_name: "WhatsappMessage",
           foreign_key: :transaction_id, dependent: :nullify, inverse_of: :linked_transaction

  # up-tier F5: the durable receipt (photo/PDF). WhatsApp receipts copy the SAME blob here
  # so the image outlives the 60-day WA media purge; manual rows upload one on the form.
  # dependent defaults to :purge_later — hard-destroying the row purges the bytes (LGPD).
  has_one_attached :receipt do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 96, 96 ]
  end

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

  # Receipt gates (up-tier F5, the DocumentImport lesson): browsers/clients send unreliable
  # MIME types, so a receipt must both declare an allowed type AND carry the DECLARED
  # format's real magic bytes (an .exe renamed .jpg fails the byte probe; so does a PDF
  # blob declared image/webp — the probe is keyed by the declared type).
  MAX_RECEIPT_BYTES     = 10.megabytes
  RECEIPT_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic application/pdf].freeze
  RECEIPT_MAGIC_BYTES = {
    "image/jpeg"      => ->(head) { head.start_with?("\xFF\xD8\xFF".b) },
    "image/png"       => ->(head) { head.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/webp"      => ->(head) { head[0, 4] == "RIFF" && head[8, 4] == "WEBP" },
    "image/heic"      => ->(head) { head[4, 4] == "ftyp" && %w[heic heix heim heis hevc mif1 msf1].include?(head[8, 4]) },
    "application/pdf" => ->(head) { head.start_with?("%PDF-".b) }
  }.freeze

  validates :amount_cents, numericality: { only_integer: true }
  validates :occurred_on, presence: true
  validates :billing_month, presence: true
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true
  # Only when a new receipt is being attached on this save (never re-reads a settled blob).
  validate :receipt_acceptable,
           if: -> { attachment_changes["receipt"].is_a?(ActiveStorage::Attached::Changes::CreateOne) }
  # A posted transfer needs both accounts, distinct, and no card. Model-level (not a DB check)
  # so a low-confidence WA transfer can still park in pending_review with slots missing.
  validate :transfer_shape, if: -> { posted? && transfer? }

  # The universal month key is computed here (before_validation, so the presence check + DB
  # NOT NULL both see it) at every non-guarded write path — unless the row was manually moved.
  # guarded_update (update_all) skips this by design and never touches occurred_on / instrument.
  before_validation :assign_billing_month

  # Denormalized key for merchant memory (Categories::Suggest); kept in sync on every
  # callback-bearing write. guarded_update (update_all) never touches merchant by design.
  before_save :assign_merchant_norm, if: :merchant_changed?

  # .kept folded into the composed scopes = the single aggregate choke point (doc 05 §2.5):
  # MonthSummary, the ledger, bill_cents, inbox all read through these. Enum status scopes and
  # idempotency finders (find_by(source_message_id:), guarded_update) stay unscoped by design.
  scope :spend, -> { posted.kept.where(direction: "expense") }         # excludes rejected/superseded
  scope :posted_in, ->(month) { posted.kept.where(billing_month: month) }   # the ledger scope + every aggregate
  scope :occurred_between, ->(from, to) { posted.kept.where(occurred_on: from..to) }  # the "Hoje" purchase-date window
  # The single definition of "a goal contribution": posted transfers landing in the given
  # savings accounts. Progress, RiskScan, Replan and the accounts-page earmark split all read
  # this one scope (goals round-4 review) — callers add their own billing_month window.
  scope :guardado_into, ->(bank_account_ids) { posted.kept.where(direction: "transfer", transfer_to_bank_account_id: bank_account_ids) }
  scope :unassigned, -> { where(bank_account_id: nil, credit_card_id: nil) }
  scope :in_app_inbox, -> { kept.where(status: %w[pending_review needs_confirmation needs_clarification needs_disambiguation]) }

  # Rows the backfill run anchored at `at` auto-categorized: machine-stamped, existed before
  # the run, touched by it. Drives the ledger banner count and the one-click undo.
  scope :auto_categorized_since, lambda { |at|
    kept.where(category_source: %w[memory ai]).where("updated_at >= ? AND created_at < ?", at, at)
  }

  # The in-app pending inbox (.plans/whats §5.8): open/pending asks PLUS posted expenses with
  # no instrument yet (auto-committed, waiting for the user to pick an account in-app).
  scope :pending_inbox, lambda {
    kept.where("status IN (:pending) OR (status = 'posted' AND bank_account_id IS NULL AND credit_card_id IS NULL)",
               pending: PENDING_INBOX_STATUSES)
  }

  # The single outstanding confirm/clarify question for a SENDER within their account (spine
  # D6: the ask conversation is per phone). The next inbound reply is routed to this.
  def self.open_ask_for(user)
    where(account: user.account, created_by: user, status: OPEN_ASK_STATUSES)
      .kept
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

  # Assign (or reassign) the instrument in-app; clears the other side. Resets the manual
  # billing-month flag (the override was per-card context) and lets assign_billing_month
  # recompute — update! fires callbacks (unlike guarded_update).
  def assign_instrument!(record)
    case record
    when BankAccount then update!(bank_account: record, credit_card: nil, billing_month_manual: false)
    when CreditCard  then update!(credit_card: record, bank_account: nil, billing_month_manual: false)
    else raise ArgumentError, "not an instrument: #{record.class}"
    end
  end

  private
    def assign_merchant_norm
      self.merchant_norm = TextMatch.normalize(merchant).presence
    end

    # Recompute billing_month from occurred_on + instrument, unless the row was manually moved
    # (R2 sticky). Card rows use the closing rule; card PARCELS stagger by installment_number so
    # every recompute reproduces the fan-out instead of collapsing it. Bank/unassigned rows =
    # calendar month. Never NULL.
    def assign_billing_month
      return if billing_month_manual? || occurred_on.blank?
      self.billing_month =
        if credit_card
          m = credit_card.billing_month_for(occurred_on)
          installment_number ? m >> (installment_number - 1) : m
        else
          occurred_on.beginning_of_month
        end
    end

    def transfer_shape
      if bank_account_id.blank? || transfer_to_bank_account_id.blank?
        errors.add(:transfer_to_bank_account, :blank)
      elsif transfer_to_bank_account_id == bank_account_id
        errors.add(:transfer_to_bank_account, :same_account)
      end
      errors.add(:credit_card, :present) if credit_card_id.present?
    end

    # Size + declared-type + magic-byte gates in one validation (imports re-derive the real
    # format in a job; a receipt is served back to the user, so it is checked before persisting).
    def receipt_acceptable
      change = attachment_changes["receipt"]
      errors.add(:receipt, :too_large) if change.blob.byte_size > MAX_RECEIPT_BYTES
      unless RECEIPT_CONTENT_TYPES.include?(change.blob.content_type) && receipt_magic_bytes_ok?(change)
        errors.add(:receipt, :unsupported_type)
      end
    end

    # The probe is looked up by the DECLARED content type — the bytes must match what the
    # client claims, not just any allowed format (a %PDF- blob declared image/webp fails).
    def receipt_magic_bytes_ok?(change)
      probe = RECEIPT_MAGIC_BYTES[change.blob.content_type]
      return false unless probe
      probe.call(receipt_head_bytes(change.attachable).to_s.b)
    end

    # First bytes of the attachable, whatever shape it arrived in: an existing blob (the
    # WhatsApp copy path), an uploaded file, or an io: hash.
    def receipt_head_bytes(attachable)
      case attachable
      when ActiveStorage::Blob
        head = +""
        attachable.download do |chunk|
          head << chunk
          break if head.bytesize >= 16
        end
        head
      when Hash
        read_head(attachable[:io])
      else
        read_head(attachable)
      end
    end

    def read_head(io)
      return "" unless io.respond_to?(:read) && io.respond_to?(:rewind)
      io.rewind
      head = io.read(16).to_s
      io.rewind
      head
    end
end
