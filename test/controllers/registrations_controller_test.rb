require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "valid sign-up creates an UNCONFIRMED user with NO session and enqueues one verification email" do
    assert_difference "User.count", 1 do
      assert_enqueued_emails 1 do
        post registration_url, params: { user: {
          email_address: "new@example.com", password: "password123", password_confirmation: "password123" } }
      end
    end
    assert_redirected_to new_session_url                  # hard gate: sent to sign-in, NOT signed in
    assert cookies[:session_id].blank?
    assert_not User.find_by(email_address: "new@example.com").verified?
  end

  test "blank password is rejected with 422" do
    assert_no_difference "User.count" do
      post registration_url, params: { user: { email_address: "x@example.com", password: "", password_confirmation: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "duplicate email is rejected with 422" do
    assert_no_difference "User.count" do
      post registration_url, params: { user: {
        email_address: "confirmed@example.com", password: "password123", password_confirmation: "password123" } }
    end
    assert_response :unprocessable_entity
  end

  test "sign-up is blocked for an address off the allowlist" do
    with_allowed_emails([ "allowed@example.com" ]) do
      assert_no_difference "User.count" do
        post registration_url, params: { user: {
          email_address: "intruder@example.com", password: "password123", password_confirmation: "password123" } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "sign-up succeeds for an allowlisted address" do
    with_allowed_emails([ "allowed@example.com" ]) do
      assert_difference "User.count", 1 do
        post registration_url, params: { user: {
          email_address: "allowed@example.com", password: "password123", password_confirmation: "password123" } }
      end
      assert_redirected_to new_session_url
    end
  end
end
