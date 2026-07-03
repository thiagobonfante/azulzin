class PasswordsMailer < ApplicationMailer
  def reset
    @user = params[:user]
    mail subject: default_i18n_subject, to: @user.email_address
  end
end
