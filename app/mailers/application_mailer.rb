class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@azulzin.com.br"
  around_action :set_locale        # email language = recipient's preference, not the caller's
  layout "mailer"

  private
    def set_locale(&block)
      I18n.with_locale(params&.dig(:user)&.locale || I18n.default_locale, &block)
    end
end
