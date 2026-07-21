class ApplicationController < ActionController::Base
  include Authentication

  # A blocked (non-allowlisted) sign-in attempt lands back on the sign-in page.
  rescue_from Authentication::NotAllowed do
    redirect_to new_session_path, alert: t("shared.not_allowed")
  end

  around_action :switch_locale

  # Hotwire Native shells (UA carries "Turbo Native"/"Hotwire Native") render the
  # chrome-less +native layout/partial variants. turbo_native_app? comes from turbo-rails.
  before_action :set_native_variant

  # Native cold-start CSRF race: the durable session_id cookie is permanent but the Rails
  # cookie session (home of _csrf_token) dies with the app process, so the shells' N
  # parallel first GETs each mint a *different* token and only the last Set-Cookie wins
  # the shared jar — orphaning every other page's form. Seeding the token
  # deterministically from the durable session makes all parallel mints agree, so any
  # page's token verifies against any winner cookie. No-op when signed out.
  before_action :stabilize_csrf_token

  # View-side owner predicate (D9): belt-and-suspenders with require_owner!. Owner-only controls
  # are hidden for members in the view AND enforced server-side.
  helper_method :account_owner?
  def account_owner? = Current.user&.account_membership&.owner? || false

  # Money movements need somewhere to land: an account with no bank account and no card
  # (e.g. onboarding skipped) can't create transactions/commitments until one exists.
  helper_method :account_has_instruments?
  def account_has_instruments?
    Current.account.bank_accounts.kept.any? || Current.account.credit_cards.kept.any?
  end

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # True on the product-app host (always true in dev/test, where the host split is off).
  # Exposed to views so PWA tags (manifest link / SW registration) only render on the app host.
  helper_method :on_app_host?

  private
    def on_app_host?
      !Rails.env.production? || request.host == Rails.application.config.x.app_host
    end

    # Onboarding gate: authenticated users who haven't finished the wizard are sent to it.
    # Runs after require_authentication, so Current.user is present.
    def require_onboarding
      redirect_to onboarding_path unless Current.user&.onboarded?
    end

    def switch_locale(&action)
      I18n.with_locale(resolve_locale, &action)
    end

    def set_native_variant
      request.variant = :native if turbo_native_app?
    end

    def stabilize_csrf_token
      resume_session
      return unless Current.session
      session[:_csrf_token] = Base64.urlsafe_encode64(
        OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "csrf:#{Current.session.id}"),
        padding: false
      )
    end

    # Forced to the pt-BR default for now: the browser (Accept-Language), the ?locale
    # param, the session, and the saved user locale are all ignored. The language
    # switcher is a no-op until this is reverted — restore the resolve chain below to
    # re-enable en-US:
    #   supported = Rails.application.config.x.supported_locales.keys
    #   candidate = params[:locale] || session[:locale] || Current.user&.locale
    #   candidate = http_accept_language.compatible_language_from(supported) if candidate.blank?
    #   supported.include?(candidate.to_s) ? candidate : I18n.default_locale
    def resolve_locale
      I18n.default_locale
    end
end
