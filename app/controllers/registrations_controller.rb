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
      # Non-invite signup owns a fresh solo account (Phase 4 will skip this when a pending
      # invite token is in session; ensure_membership_for is the sign-in safety net either way).
      Accounts::Bootstrap.call(@user)
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
