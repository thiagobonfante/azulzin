require "test_helper"

# Real-crypto check of the native-SSO trust boundary: tokens signed by a key we
# control, served through a stubbed JWKS. Uses the apple config (aud is a constant;
# google differs only in config values, the code path is identical).
class Auth::IdTokenTest < ActiveSupport::TestCase
  KEY = OpenSSL::PKey::RSA.generate(2048)
  JWK = JWT::JWK.new(KEY.public_key)
  JWKS = { keys: [ JWK.export ] }

  def claims(overrides = {})
    { "iss" => "https://appleid.apple.com", "aud" => Auth::IdToken::APPLE_BUNDLE_ID,
      "exp" => 1.hour.from_now.to_i, "sub" => "apple-1",
      "email" => "a@example.com", "email_verified" => "true" }.merge(overrides)
  end

  def sign(payload) = JWT.encode(payload, KEY, "RS256", kid: JWK.kid)

  def verify(token)
    Auth::IdToken.stub(:jwks_for, ->(_url, invalidate: false) { JWKS }) do
      Auth::IdToken.verify(token, provider: "apple")
    end
  end

  test "a well-signed token with the right iss/aud/exp verifies" do
    assert_equal "apple-1", verify(sign(claims))["sub"]
  end

  test "a token for someone else's app (wrong aud) is refused" do
    assert_nil verify(sign(claims("aud" => "br.com.other.app")))
  end

  test "a token from the wrong issuer is refused" do
    assert_nil verify(sign(claims("iss" => "https://accounts.google.com")))
  end

  test "an expired token is refused" do
    assert_nil verify(sign(claims("exp" => 1.minute.ago.to_i)))
  end

  test "a token signed by an unknown key is refused" do
    other = OpenSSL::PKey::RSA.generate(2048)
    forged = JWT.encode(claims, other, "RS256", kid: JWT::JWK.new(other.public_key).kid)
    assert_nil verify(forged)
  end

  test "garbage and blank tokens are refused" do
    assert_nil verify("not-a-jwt")
    assert_nil verify("")
  end
end
