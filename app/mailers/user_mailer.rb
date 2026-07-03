class UserMailer < ApplicationMailer
  def email_verification
    @user = params[:user]                    # ApplicationMailer#set_locale reads params[:user].locale
    @url  = email_verification_url(token: @user.generate_token_for(:email_verification))
    mail to: @user.email_address, subject: default_i18n_subject   # user_mailer.email_verification.subject
  end
end
