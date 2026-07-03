class ApplicationController < ActionController::Base
  include Authentication

  around_action :switch_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    def switch_locale(&action)
      I18n.with_locale(resolve_locale, &action)
    end

    def resolve_locale
      supported = Rails.application.config.x.supported_locales.keys       # %w[pt-BR en-US]
      candidate = params[:locale] || session[:locale] || Current.user&.locale
      candidate = http_accept_language.compatible_language_from(supported) if candidate.blank?
      supported.include?(candidate.to_s) ? candidate : I18n.default_locale  # whitelist — mandatory
    end
end
