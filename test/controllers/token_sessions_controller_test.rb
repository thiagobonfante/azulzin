require "test_helper"

# Native SSO endpoint (.plans/mobile/10). Auth::IdToken is stubbed — it is the trust
# boundary, unit-tested with real crypto in test/services/auth/id_token_test.rb;
# everything past it (linking rules, bootstrap, allowlist, session) runs real.
class TokenSessionsControllerTest < ActionDispatch::IntegrationTest
  def payload(email:, uid: "N-1", verified: true)
    { "sub" => uid, "email" => email, "email_verified" => verified }
  end

  def post_token(provider: "google_oauth2", **payload_opts)
    Auth::IdToken.stub :verify, payload(**payload_opts) do
      post "/auth/#{provider}/token", params: { id_token: "stubbed" }
    end
  end

  test "verified Google token creates a confirmed user, an identity, and a session" do
    assert_difference [ "User.count", "OauthIdentity.count" ], 1 do
      post_token(email: "native@example.com")
    end
    user = User.find_by(email_address: "native@example.com")
    assert user.verified?
    assert_equal "google_oauth2", user.oauth_identities.sole.provider
    assert cookies[:session_id].present?
    assert_redirected_to root_url   # after_authentication_url; root then routes onboarding
  end

  test "Apple token resolves to the same rules under provider apple" do
    assert_difference [ "User.count", "OauthIdentity.count" ], 1 do
      post_token(provider: "apple", email: "apple@example.com", uid: "A-1")
    end
    assert_equal "apple", User.find_by(email_address: "apple@example.com").oauth_identities.sole.provider
    assert cookies[:session_id].present?
  end

  test "verified token links an existing password user and backfills confirmation" do
    existing = users(:unconfirmed)
    assert_no_difference "User.count" do
      assert_difference "OauthIdentity.count", 1 do
        post_token(email: existing.email_address)
      end
    end
    assert existing.reload.verified?
  end

  test "UNVERIFIED email never links to an existing password account" do
    assert_no_difference [ "User.count", "OauthIdentity.count" ] do
      post_token(email: users(:confirmed).email_address, verified: false)
    end
    assert_redirected_to new_session_url
    assert cookies[:session_id].blank?
  end

  test "an invalid token is refused" do
    Auth::IdToken.stub :verify, nil do
      assert_no_difference [ "User.count", "OauthIdentity.count" ] do
        post "/auth/google_oauth2/token", params: { id_token: "garbage" }
      end
    end
    assert_redirected_to new_session_url
    assert cookies[:session_id].blank?
  end

  test "token sign-in is refused when the address is off the allowlist" do
    with_allowed_emails([ "someone-else@example.com" ]) do
      post_token(email: "intruder@example.com")
      assert_redirected_to new_session_url
      assert cookies[:session_id].blank?
    end
  end

  test "unknown providers do not route" do
    post "/auth/facebook/token", params: { id_token: "x" }
    assert_response :not_found
  end
end
