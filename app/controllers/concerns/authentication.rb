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

    # Invariant: a signed-in user ALWAYS has exactly one membership when this returns. Phase 4
    # adds invitation-token consumption here (doc 02 §3); for now only the Bootstrap fallback.
    def ensure_membership_for(user)
      Accounts::Bootstrap.call(user) if user.account_membership.nil?
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
