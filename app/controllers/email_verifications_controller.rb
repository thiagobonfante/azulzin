class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: %i[show create]   # link + resend both work logged-out
  rate_limit to: 5, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: t("shared.rate_limited") }

  def show
    if (user = User.find_by_token_for(:email_verification, params[:token]))
      user.verify!
      start_new_session_for user                         # confirmation click doubles as first sign-in
      redirect_to root_path, notice: t(".confirmed")
    else
      redirect_to new_session_path, alert: t(".invalid")
    end
  end

  def create                                            # resend by email address; identical reply either way
    user = User.find_by(email_address: params[:email_address])
    UserMailer.with(user: user).email_verification.deliver_later if user && !user.verified?
    redirect_to new_session_path, notice: t(".sent")
  end
end
