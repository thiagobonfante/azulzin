class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: t("shared.rate_limited") }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      # Non-invite signup owns a fresh solo account; an invited signup skips it and joins the
      # inviter's account at first sign-in (ensure_membership_for). doc 02 §3.2.
      Accounts::Bootstrap.call(@user) unless pending_invitation_in_session?
      UserMailer.with(user: @user).email_verification.deliver_later
      redirect_to new_session_path, status: :see_other, notice: t(".check_email")
    else
      render :new, status: :unprocessable_entity           # Turbo re-renders inline errors
    end
  end

  private
    def registration_params
      params.expect(user: %i[email_address password password_confirmation])
    end
end
