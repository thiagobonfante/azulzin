# Native SSO (.plans/mobile/10): the shells' "sign-in" bridge component gets an ID
# token from the platform SDK and the signed-out page POSTs it here — the webview
# itself making the POST is what lands the session cookie in it. Auth::IdToken is the
# trust boundary; past it, this mirrors OmniauthCallbacksController#create exactly.
# CSRF: a real form POST from the page, so standard forgery protection applies.
class TokenSessionsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes,
             with: -> { redirect_to new_session_path, alert: t("shared.rate_limited") }

  def create
    payload = Auth::IdToken.verify(params[:id_token].to_s, provider: params[:provider])
    user    = payload && User.from_omniauth(auth_hash(payload),
                                            skip_account_bootstrap: pending_invitation_in_session?)
    if user&.persisted?
      start_new_session_for user
      redirect_to after_authentication_url, notice: t("omniauth.signed_in")
    else
      redirect_to new_session_path, alert: t("omniauth.could_not_sign_in")
    end
  end

  private

  # The same shape the OmniAuth strategies emit — provider + uid ("sub") match what the
  # web flow writes to OauthIdentity, so both flows resolve to the same user, and
  # User.from_omniauth (linking rules, bootstrap, allowlist via start_new_session_for)
  # is shared verbatim.
  def auth_hash(payload)
    OmniAuth::AuthHash.new(
      provider: params[:provider],
      uid:      payload["sub"],
      info:     { email: payload["email"] },
      extra:    { raw_info: payload }
    )
  end
end
