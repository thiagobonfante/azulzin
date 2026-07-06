module Authentication
  extend ActiveSupport::Concern

  # Raised when an allowlisted-only deployment refuses to sign a user in.
  # ApplicationController rescues it back to the sign-in page. See User#email_allowed?.
  class NotAllowed < StandardError; end

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      raise NotAllowed unless user.email_allowed?   # allowlist gate — covers every sign-in path
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
      ensure_membership_for(user)                   # after Current.session is set; never account-less
    end

    # Invariant: a signed-in user ALWAYS has exactly one membership when this returns. Consumes a
    # short-TTL invite token (doc 02 §3) — token possession is the credential, so it works across
    # password / OAuth / verification-click — then the Bootstrap fallback guarantees no account.
    INVITATION_TOKEN_TTL = 30.minutes   # doc 02 §2.2: a session cookie can outlive intent

    def ensure_membership_for(user)
      token     = session.delete(:invitation_token)
      stored_at = session.delete(:invitation_token_at)
      if token && stored_at && Time.at(stored_at.to_i) > INVITATION_TOKEN_TTL.ago
        result = Invitations::Accept.call(user: user, token: token)
        flash[:alert] = t("invitations.errors.#{result.error}") if result && !result.ok
      end
      # reload the association: Accept created the membership on the account's side, so a stale
      # nil cache here would double-bootstrap and trip the one-membership-per-user unique index.
      Accounts::Bootstrap.call(user) if user.reload_account_membership.nil?
    end

    # A pending invite token in session ⇒ signup paths skip own-account bootstrap (membership
    # materializes at first sign-in via the hook above). doc 02 §3.2/§3.3.
    def pending_invitation_in_session?
      Invitation.find_by(token: session[:invitation_token])&.pending? || false
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
