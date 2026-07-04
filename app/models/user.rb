class User < ApplicationRecord
  # validations: false — OAuth-only users legitimately have a NULL password_digest.
  # reset_token stays true (the default), so password_reset_token +
  # find_by_password_reset_token! remain available (verified in activemodel 8.1.3).
  has_secure_password validations: false

  has_many :sessions,         dependent: :destroy
  has_many :oauth_identities, dependent: :destroy   # table added in Phase 4
  has_many :bank_accounts,    dependent: :destroy
  has_many :credit_cards,     dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  # Phone is stored as E.164 digits (country code + national number). The profile form
  # supplies the two parts separately (country_code + phone_national) and compose_phone
  # joins them; direct assignment (seeds/tests) is just kept as digits.
  normalizes :phone, with: ->(p) { p.to_s.gsub(/\D/, "") }

  # Profile phone entry: a country dial code (Brazil by default) + the national number,
  # joined into E.164 by compose_phone. Both are virtual (form-only, no columns).
  DEFAULT_DIAL_CODE = "55"
  # Flag emoji + dial code, Brazil first — the country selector in the profile step.
  PHONE_DIAL_CODES = [
    [ "🇧🇷", "55" ], [ "🇵🇹", "351" ], [ "🇺🇸", "1" ],  [ "🇦🇷", "54" ],
    [ "🇺🇾", "598" ], [ "🇵🇾", "595" ], [ "🇨🇱", "56" ], [ "🇨🇴", "57" ],
    [ "🇲🇽", "52" ],  [ "🇪🇸", "34" ],  [ "🇬🇧", "44" ], [ "🇫🇷", "33" ],
    [ "🇩🇪", "49" ],  [ "🇮🇹", "39" ],  [ "🇯🇵", "81" ]
  ].freeze
  attr_accessor :country_code, :phone_national

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

  # Onboarding step 1 (profile) requirements — enforced only in the :profile context so
  # sign-up and OAuth account creation (which never touch name/phone) stay unaffected.
  before_validation :compose_phone, on: :profile
  validates :name,  presence: true, length: { maximum: 120 }, on: :profile
  validates :phone, presence: true, format: { with: /\A\d{8,15}\z/ }, on: :profile   # E.164 range

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address        # changing the address invalidates a pending link
  end

  def verified? = confirmed_at.present?
  def verify!   = update!(confirmed_at: Time.current)

  # Onboarding wizard: complete once the user has finished the setup steps.
  def onboarded? = onboarded_at.present?
  def onboard!   = update!(onboarded_at: Time.current)

  # Step 1 of the wizard. Validates name/phone in the :profile context only, leaving
  # sign-up untouched.
  def update_as_profile(attributes)
    assign_attributes(attributes)
    save(context: :profile)
  end

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

    # Join the chosen country dial code with the typed national number into E.164 digits.
    # Only runs in the :profile context and only when the form supplied a national number.
    def compose_phone
      return if phone_national.blank?

      dial = country_code.to_s.gsub(/\D/, "").presence || DEFAULT_DIAL_CODE
      self.phone = "#{dial}#{phone_national.gsub(/\D/, '')}"
    end
end
