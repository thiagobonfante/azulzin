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
  # Hardcoded allowlist gate (config.x.allowed_emails, prod only). Blocks account
  # creation — password sign-up and OAuth create alike; sign-in is gated separately
  # in Authentication#start_new_session_for. Blank list ⇒ unrestricted (dev/test).
  validate :email_address_on_allowlist, on: :create

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address        # changing the address invalidates a pending link
  end

  def verified? = confirmed_at.present?
  def verify!   = update!(confirmed_at: Time.current)

  # Single source of truth for the allowlist gate (config.x.allowed_emails, prod only).
  # Blank/unset list ⇒ everyone is allowed, so dev+test stay unrestricted.
  def self.email_allowed?(email)
    allowed = Rails.configuration.x.allowed_emails
    allowed.blank? || allowed.include?(email.to_s.strip.downcase)
  end

  def email_allowed? = self.class.email_allowed?(email_address)

  def self.from_omniauth(auth)
    return if auth.nil?   # unconfigured provider slips past the route → refuse, don't 500

    # 1) Known identity → its user (email-independent, primary lookup)
    if (identity = OauthIdentity.find_by(provider: auth.provider, uid: auth.uid))
      return identity.user
    end

    email    = auth.info.email&.strip&.downcase
    verified = provider_email_verified?(auth)

    transaction do
      # 2) Link to an existing password account ONLY when the provider verified the email
      user = (find_by(email_address: email) if verified && email.present?)
      if user
        user.update!(confirmed_at: Time.current) unless user.verified?   # backfill on verified link
      else
        # 3) Otherwise create a new account with a random (resettable) password
        user = create!(
          email_address: email,
          password:      SecureRandom.base58(32),
          confirmed_at:  (Time.current if verified)
        )
      end
      user.oauth_identities.create!(provider: auth.provider, uid: auth.uid)
      user
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil   # duplicate email (unverified match) or a concurrent-login race → safe refusal
  end

  def self.provider_email_verified?(auth)
    auth.provider == "google_oauth2" &&
      auth.dig("extra", "raw_info", "email_verified").to_s == "true"
  end

  private
    def email_address_on_allowlist
      errors.add(:email_address, :not_allowed) unless email_allowed?
    end
end
