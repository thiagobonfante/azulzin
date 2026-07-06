# A pending, token-addressed offer to join an account (spine D4). Plaintext base58 token
# (single-use, low-value); persistent row so we get list/revoke/resend + the partial-unique
# "one open invite per email per account". Controller/mailer land in Phase 4 (doc 02).
class Invitation < ApplicationRecord
  EXPIRY = 7.days

  belongs_to :account
  belongs_to :invited_by, class_name: "User", optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate  :under_cap,          on: :create   # soft check, UX only (doc 02 §4)
  validate  :email_on_allowlist, on: :create   # temporary prod gate parity (doc 02 §1.3)
  validate  :not_already_a_member, on: :create

  before_create do
    self.token      ||= SecureRandom.base58(32)
    self.expires_at ||= EXPIRY.from_now
  end

  scope :open,    -> { where(accepted_at: nil) }                   # what the unique index sees
  scope :pending, -> { open.where(expires_at: Time.current..) }    # actually acceptable

  def pending? = accepted_at.nil? && expires_at.future?

  # Create OR refresh-and-resend: the partial unique index forbids a second open row for the
  # same email, so "resend" regenerates token+expiry on the existing row. One entry point
  # keeps InvitationsController#create the only write path.
  def self.issue!(account:, email:, invited_by:)
    normalized = email.to_s.strip.downcase
    if (existing = account.invitations.open.find_by(email: normalized))
      existing.update!(token: SecureRandom.base58(32), expires_at: EXPIRY.from_now,
                       invited_by: invited_by, accepted_at: nil)
      existing
    else
      account.invitations.create!(email: normalized, invited_by: invited_by)
    end
  end

  private
    def under_cap
      taken = account.members_count + account.invitations.pending.where.not(email: email).count
      errors.add(:base, :cap_reached) if taken >= Account::MAX_MEMBERS
    end

    def email_on_allowlist
      errors.add(:email, :not_allowed) unless User.email_allowed?(email)
    end

    def not_already_a_member
      errors.add(:email, :already_member) if
        account.memberships.joins(:user).exists?(users: { email_address: email })
    end
end
