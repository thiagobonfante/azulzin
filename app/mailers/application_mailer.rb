class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@azulzin.com.br"
  around_action :set_locale        # pinned to pt-BR for now (see below)
  layout "mailer"

  private
    # Pinned to the pt-BR default for now, matching the force-pinned web UI
    # (ApplicationController#resolve_locale). Restore the recipient's own preference
    # when en-US is re-enabled:
    #   I18n.with_locale(params&.dig(:user)&.locale || I18n.default_locale, &block)
    def set_locale(&block)
      I18n.with_locale(I18n.default_locale, &block)
    end
end
