class User < ApplicationRecord
  # validations: false — OAuth-only users legitimately have a NULL password_digest.
  # reset_token stays true (the default), so password_reset_token +
  # find_by_password_reset_token! remain available (verified in activemodel 8.1.3).
  has_secure_password validations: false

  has_one  :account_membership, dependent: :destroy
  has_one  :account, through: :account_membership
  has_many :sessions,          dependent: :destroy
  has_many :oauth_identities,  dependent: :destroy   # table added in Phase 4
  # The 7 domain tables now belong to the Account (spine D2); the LGPD cascade lives on
  # Account. No reverse has_many here — attribution reverse-lookups, if ever needed, go
  # through explicit queries; we don't ship speculative associations.
  has_many :whatsapp_messages, dependent: :nullify   # sender attribution survives as NULL (D8)

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

  # Human label for the members list + attribution chips (doc 06). Never blank.
  def display_name = name.to_s.strip.presence || email_address

  # Onboarding wizard: complete once the user has finished the setup steps. Seeds the default
  # categories (idempotent) as part of finishing.
  def onboarded? = onboarded_at.present?
  def onboard!
    # First seeder's locale sticks: any kept category ⇒ the account is already seeded (or
    # curated) — never reseed, especially not in a second language (doc 03 / D5).
    Categories::SeedDefaults.call(account, locale: locale) if account.categories.kept.none?
    update!(onboarded_at: Time.current)
  end

  # Import proposals still awaiting a decision — drives the derived hub nudge (.plans/auto, D6).
  # Imports belong to the account now (spine D2), so count over the shared account's imports.
  def proposed_import_count
    account.document_imports.awaiting_review.sum { it.proposed_items.size }
  end

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

  def self.from_omniauth(auth, skip_account_bootstrap: false)
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
        # Non-invite OAuth signup owns a fresh solo Account; an invited signup skips it (the
        # controller passes skip_account_bootstrap: from a pending invite token). The link branch
        # already has an account / gets the sign-in fallback.
        Accounts::Bootstrap.call(user) unless skip_account_bootstrap
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

  # --- WhatsApp channel identity (see .plans/whats §3.3, Review P0-1) ---

  def phone_verified? = phone_verified_at.present?

  # Generate (idempotently, unless :force) the short code the user texts to the commercial
  # number to prove ownership. Unambiguous alphabet (no O/0/I/1). Retries on the rare
  # unique-index collision.
  VERIFICATION_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  def whatsapp_verification_code!(force: false)
    return whatsapp_verification_code if whatsapp_verification_code.present? && !force
    begin
      update!(whatsapp_verification_code: "AZUL-#{Array.new(4) { VERIFICATION_ALPHABET.sample }.join}")
    rescue ActiveRecord::RecordNotUnique
      retry
    end
    whatsapp_verification_code
  end

  # Bind an inbound sender's number to this account and mark it verified. Called from the
  # webhook when an unverified sender texts a matching code. Idempotent-safe: the unique
  # whatsapp_id index refuses a second account claiming the same number.
  def verify_whatsapp!(sender_jid)
    digits = sender_jid.to_s.gsub(/\D/, "")   # strips @c.us / @lid → stable numeric identity
    update!(whatsapp_id: digits, whatsapp_jid: sender_jid.to_s, phone_verified_at: Time.current,
            whatsapp_verification_code: nil)
  end

  # Keep the outbound reply address current (the JID can move between @c.us and @lid). Called
  # from the webhook on every inbound message from an already-verified user. update_column so
  # it never trips validations or touches updated_at noise on a hot path.
  def refresh_whatsapp_jid!(sender_jid)
    update_column(:whatsapp_jid, sender_jid.to_s) if sender_jid.present? && whatsapp_jid != sender_jid.to_s
  end

  # Resolve a verification code typed into a WhatsApp message to the user awaiting it, or
  # nil. Matches the code as a whole token anywhere in the body (case-insensitive), so
  # "meu codigo AZUL-4F3K" works.
  def self.awaiting_whatsapp_verification(body)
    codes = body.to_s.upcase.scan(/AZUL-[A-Z0-9]{4}/)
    return nil if codes.empty?
    where(whatsapp_verification_code: codes).where(phone_verified_at: nil).first
  end

  # The verified user for an inbound WhatsApp JID, or nil. NEVER guesses: resolves by
  # exact equality on the unique `whatsapp_id`, and REFUSES an ambiguous (0 or ≥2) match
  # rather than attributing money to an arbitrary row.
  def self.verified_for_wa(jid)
    ids = wa_id_candidates(jid)
    return nil if ids.empty?
    scope = where.not(phone_verified_at: nil).where(whatsapp_id: ids)
    scope.limit(2).count == 1 ? scope.first : nil   # 0 or ≥2 → refuse
  end

  # Digits-only candidates for a JID, tolerant of the Brazilian mobile 9th digit which
  # WhatsApp sometimes includes/omits. Only ever compared against a VERIFIED whatsapp_id.
  def self.wa_id_candidates(jid)
    digits = jid.to_s.sub(/@c\.us\z/, "").gsub(/\D/, "")
    return [] if digits.length < 12
    cc_ddd, rest = digits[0, 4], digits[4..]
    out = [ digits ]
    out << cc_ddd + rest[1..]      if rest.length == 9 && rest[0] == "9"   # drop the 9
    out << cc_ddd + "9" + rest     if rest.length == 8                     # add the 9
    out.uniq
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
