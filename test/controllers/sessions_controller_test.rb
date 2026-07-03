require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "valid credentials sign in and set a session cookie" do
    post session_url, params: { email_address: "confirmed@example.com", password: "password123" }
    assert_response :redirect
    assert cookies[:session_id].present?
  end

  test "invalid credentials do not create a session" do
    post session_url, params: { email_address: "confirmed@example.com", password: "wrong" }
    assert_redirected_to new_session_url
    assert cookies[:session_id].blank?
  end

  test "sign out clears the session" do
    post session_url, params: { email_address: "confirmed@example.com", password: "password123" }
    delete session_url
    assert_response :see_other
    assert cookies[:session_id].blank?
  end

  test "an unconfirmed user cannot sign in with a password" do
    post session_url, params: { email_address: "unconfirmed@example.com", password: "password123" }
    assert_redirected_to new_session_url
    assert cookies[:session_id].blank?
  end
end
