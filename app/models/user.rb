class User < ApplicationRecord
  # validations: false — OAuth-only users legitimately have a NULL password_digest.
  # reset_token stays true (the default), so password_reset_token +
  # find_by_password_reset_token! remain available (verified in activemodel 8.1.3).
  has_secure_password validations: false

  has_many :sessions,         dependent: :destroy
  has_many :oauth_identities, dependent: :destroy   # table added in Phase 4

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  # Length/confirmation only when a password is actually set (OAuth users: allow_nil).
  validates :password, length: { minimum: 8 }, confirmation: true, allow_nil: true
  # Presence on create catches blank sign-up passwords (password = "" is a no-op the
  # setter drops to nil). OAuth create supplies a random password, so it passes too.
  validates :password, presence: true, on: :create

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address        # changing the address invalidates a pending link
  end

  def verified? = confirmed_at.present?
  def verify!   = update!(confirmed_at: Time.current)
end
