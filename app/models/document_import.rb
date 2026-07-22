# One uploaded extrato/fatura on its way to becoming proposals (.plans/auto). The blob rides
# Active Storage; `fingerprint`/`extraction`/`proposals` are jsonb. Content-type + size are a
# first gate here (the job re-derives the real format from magic bytes). `checksum` (SHA256 of
# the raw bytes) dedupes per-account against live imports; a dismissed/failed one never blocks a retry.
class DocumentImport < ApplicationRecord
  include AccountScoped, Attributable   # no SoftDeletable — status lifecycle + retention is its soft delete
  belongs_to :institution, optional: true
  belongs_to :credit_card,  optional: true   # reconciliation target (.plans/credit-cards 03 §3)
  belongs_to :bank_account, optional: true
  has_one_attached :file

  MAX_FILE_BYTES = 10.megabytes
  MAX_PER_DAY    = 10
  PDF_PAGE_CAP   = 25
  # Browsers send unreliable MIME types (.ofx → application/octet-stream, .csv →
  # application/vnd.ms-excel), so a known extension also passes; the job re-derives the real
  # format from magic bytes (§6).
  ALLOWED_CONTENT_TYPES = %w[application/pdf text/csv application/x-ofx text/plain].freeze
  ALLOWED_EXTENSIONS    = %w[.pdf .csv .ofx .txt].freeze
  TERMINAL_STATUSES     = %w[extracted failed applied dismissed].freeze

  enum :status, {
    uploaded:   "uploaded",
    processing: "processing",
    extracted:  "extracted",
    failed:     "failed",
    applied:    "applied",
    dismissed:  "dismissed"
  }, default: "uploaded", validate: true

  enum :kind, { bank_statement: "bank_statement", card_bill: "card_bill", unknown: "unknown" },
       validate: { allow_nil: true }
  # A reconciliation run rides the SAME pipeline (upload → job → extraction) and branches
  # only at the tail: no proposals, the review renders the Reconciliation::Diff instead.
  enum :purpose, { onboarding: "onboarding", reconciliation: "reconciliation" },
       default: "onboarding", validate: true
  enum :source_format, { csv: "csv", ofx: "ofx", pdf: "pdf" },
       prefix: :format, validate: { allow_nil: true }

  # Dedupe is per-ACCOUNT (never created_by): a spouse re-uploading the husband's fatura hits a
  # friendly duplicate refusal, and the swapped (account_id, checksum) index would otherwise 500.
  validates :checksum, presence: true,
            uniqueness: { scope: :account_id,
                          conditions: -> { where.not(status: %w[dismissed failed]) } }
  validate :file_acceptable, on: :create

  scope :terminal,        -> { where(status: TERMINAL_STATUSES) }
  # Onboarding-only: the proposals review/apply flow must never pick up reconciliation runs.
  scope :awaiting_review, -> { where(status: "extracted", purpose: "onboarding") }

  def terminal? = TERMINAL_STATUSES.include?(status)

  # Proposals the user hasn't decided on yet — feeds the Pendências nudge (D6).
  def proposed_items = proposals.select { it["state"] == "proposed" }

  # Cheap pre-check: a live import of the same bytes already exists for this user, so don't even
  # write a blob to disk. The uniqueness validation is the authoritative guard.
  def duplicate_checksum?
    self.class.where(account_id: account_id, checksum: checksum)
        .where.not(status: %w[dismissed failed]).exists?
  end

  private

  def file_acceptable
    return errors.add(:file, :missing) unless file.attached?

    errors.add(:file, :too_large) if file.blob.byte_size > MAX_FILE_BYTES
    errors.add(:file, :unsupported_type) unless acceptable_type?
  end

  def acceptable_type?
    ALLOWED_CONTENT_TYPES.include?(file.blob.content_type) ||
      ALLOWED_EXTENSIONS.include?(File.extname(file.blob.filename.to_s).downcase)
  end
end
