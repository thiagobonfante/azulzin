class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: t("shared.rate_limited") }

  def new
    # Arriving from an invite link: pre-fill the address the invite went to (editable —
    # token possession, not the email, is the acceptance credential).
    @user = User.new(email_address: session_invitation&.email)
  end

  def create
    @user = User.new(registration_params)
    if offer_invitation_choice?
      @pending_invitation = true
      return render :new, status: :unprocessable_entity
    end
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

    # A direct signup (no invite token in session) whose email has a pending invitation pauses
    # once to ask: join via the emailed invite link (we create nothing and wait for the link),
    # or knowingly create a separate account (the re-rendered form carries skip_invitation).
    # The banner never names the inviter/account — no enumeration surface without the token.
    def offer_invitation_choice?
      params[:skip_invitation].blank? && !pending_invitation_in_session? &&
        Invitation.pending.exists?(email: @user.email_address.to_s.strip.downcase)
    end

    def session_invitation
      invitation = Invitation.find_by(token: session[:invitation_token])
      invitation if invitation&.pending?
    end
end
