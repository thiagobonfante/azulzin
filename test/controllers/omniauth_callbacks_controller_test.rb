require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup    { OmniAuth.config.test_mode = true }
  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end

  def google(email:, uid: "G-1", verified: true)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info:  { email: email },
      extra: { raw_info: { email_verified: verified } }
    )
    # In test_mode the OmniAuth middleware overwrites env["omniauth.auth"] on the
    # callback path with OmniAuth.mock_auth_for(:google_oauth2), so seed the mock too.
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config["omniauth.auth"] = auth
    get "/auth/google_oauth2/callback"
  end

  test "verified Google login creates a confirmed user, an identity, and a session" do
    assert_difference [ "User.count", "OauthIdentity.count" ], 1 do
      google(email: "g@example.com")
    end
    assert User.find_by(email_address: "g@example.com").verified?
    assert cookies[:session_id].present?
  end

  test "verified Google login links an existing password user and backfills confirmation" do
    existing = users(:unconfirmed)                     # has a password, confirmed_at nil
    assert_no_difference "User.count" do
      assert_difference "OauthIdentity.count", 1 do
        google(email: existing.email_address)
      end
    end
    assert existing.reload.verified?                   # backfilled by the verified link
  end

  test "UNVERIFIED Google login never links to an existing password account" do
    assert_no_difference [ "User.count", "OauthIdentity.count" ] do
      google(email: users(:confirmed).email_address, verified: false)
    end
    assert_redirected_to new_session_url
    assert cookies[:session_id].blank?
  end

  test "Google login is refused when the address is off the allowlist" do
    with_allowed_emails([ "someone-else@example.com" ]) do
      assert_no_difference [ "User.count", "OauthIdentity.count" ] do
        google(email: "intruder@example.com")
      end
      assert_redirected_to new_session_url
      assert cookies[:session_id].blank?
    end
  end
end
