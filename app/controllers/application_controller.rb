class ApplicationController < ActionController::Base
  include Authentication

  # A blocked (non-allowlisted) sign-in attempt lands back on the sign-in page.
  rescue_from Authentication::NotAllowed do
    redirect_to new_session_path, alert: t("shared.not_allowed")
  end

  around_action :switch_locale

  # View-side owner predicate (D9): belt-and-suspenders with require_owner!. Owner-only controls
  # are hidden for members in the view AND enforced server-side.
  helper_method :account_owner?
  def account_owner? = Current.user&.account_membership&.owner? || false

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    # True on the product-app host (always true in dev/test, where the host split is off).
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
