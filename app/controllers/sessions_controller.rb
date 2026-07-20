class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  # Signed OUT there is no durable session for stabilize_csrf_token to key on, so the
  # shells' parallel cold-start GETs can still orphan the sign-in form's token. The
  # native webviews only ever load our origin, and a browser cannot forge the Hotwire
  # Native UA cross-site (User-Agent is a forbidden fetch header), so skipping token
  # verification for the NATIVE sign-in POST does not reopen login-CSRF for browsers.
  # Web keeps full verification (pinned in test/integration/csrf_cold_start_test.rb).
  # ONE combined condition: separate only:/if: entries each disable the callback alone.
  skip_forgery_protection if: -> { action_name == "create" && turbo_native_app? }
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("shared.rate_limited") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.verified?
        start_new_session_for user
        redirect_to after_authentication_url
      else
        redirect_to new_session_path, alert: t(".unverified")
      end
    else
      redirect_to new_session_path, alert: t(".invalid")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
