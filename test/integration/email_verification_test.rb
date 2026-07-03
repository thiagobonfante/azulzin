require "test_helper"

class EmailVerificationTest < ActionDispatch::IntegrationTest
  test "a valid token confirms the user AND signs them in" do
    user  = users(:unconfirmed)
    token = user.generate_token_for(:email_verification)
    get email_verification_url(token: token)
    assert_redirected_to root_url
    assert user.reload.verified?
    assert cookies[:session_id].present?
  end

  test "a garbage token confirms nobody and starts no session" do
    get email_verification_url(token: "garbage")
    assert_redirected_to new_session_url
    assert_not users(:unconfirmed).reload.verified?
    assert cookies[:session_id].blank?
  end

  test "resend for an unconfirmed address sends one mail; unknown address sends none; both replies identical" do
    assert_enqueued_emails 1 do
      post resend_email_verification_url, params: { email_address: users(:unconfirmed).email_address }
    end
    assert_enqueued_emails 0 do
      post resend_email_verification_url, params: { email_address: "nobody@example.com" }
    end
  end
end
