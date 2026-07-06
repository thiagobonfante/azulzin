# Public invite landing + acceptance (spine D4, doc 02 §2.2). GET never changes state: for a
# signed-in visitor, acceptance can destroy their own (solo+empty) account and re-tenant them —
# doing that on a GET would be a CSRF/tenant-capture hole (SameSite=Lax doesn't cover top-level
# GET navigations). So the signed-in path renders a confirm page whose button issues a POST.
class InvitationAcceptancesController < ApplicationController
  allow_unauthenticated_access
  layout "application"       # the bare layout the auth screens use
  before_action :set_invitation

  def show
    if authenticated?
      @confirming = true     # renders inviter/account + POST button to confirm_invitation_path
    else
      store_invitation_token(@invitation.token)   # survives signup / sign-in / OAuth (§3, TTL'd)
    end
  end

  def create   # signed-in confirm — POST only, CSRF-protected
    return redirect_to accept_invitation_path(params[:token]) unless authenticated?
    result = Invitations::Accept.call(user: Current.user, token: @invitation.token)
    if result.ok
      redirect_to dashboard_path, notice: t(".joined", account: @invitation.account.name)
    else
      redirect_to dashboard_path, alert: t("invitations.errors.#{result.error}")
    end
  end

  private
    def set_invitation
      @invitation = Invitation.find_by(token: params[:token])
      # One generic message for unknown/expired/revoked — no enumeration surface.
      redirect_to(new_session_path, alert: t("invitation_acceptances.show.invalid")) unless @invitation&.pending?
    end

    # Store with a timestamp: a browser session cookie can outlive intent (shared computer), so
    # the §3 hook treats it as stale after 30 minutes.
    def store_invitation_token(token)
      session[:invitation_token]    = token
      session[:invitation_token_at] = Time.current.to_i
    end
end
