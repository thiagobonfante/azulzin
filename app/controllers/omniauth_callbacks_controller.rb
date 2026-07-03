class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access
  # The Google callback is a GET request, so Rails does not check CSRF here — no
  # skip_forgery_protection needed. The OAuth `state` param is the CSRF defense.

  def create
    auth = request.env["omniauth.auth"]
    if (user = User.from_omniauth(auth))&.persisted?
      start_new_session_for user
      redirect_to after_authentication_url, notice: t("omniauth.signed_in")
    else
      redirect_to new_session_path, alert: t("omniauth.could_not_sign_in")
    end
  end

  def failure
    redirect_to new_session_path, alert: t("omniauth.failure")
  end
end
