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

  # ── Pending invitation at direct signup: pause and ask (join by link vs separate account) ──

  def issue_invitation(email = "invitee@example.com")
    owner = users(:confirmed)
    Invitation.issue!(account: owner.account, email: email, invited_by: owner)
  end

  test "a direct signup whose email has a pending invitation pauses to ask before creating anything" do
    issue_invitation
    assert_no_difference "User.count" do
      post registration_url, params: { user: {
        email_address: "invitee@example.com", password: "password123", password_confirmation: "password123" } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("registrations.new.invitation_pending.title", locale: :"pt-BR")
    assert_includes response.body, "skip_invitation"
  end

  test "resubmitting with skip_invitation creates a separate solo account" do
    invitation = issue_invitation
    assert_difference "User.count", 1 do
      post registration_url, params: { skip_invitation: "1", user: {
        email_address: "invitee@example.com", password: "password123", password_confirmation: "password123" } }
    end
    assert_redirected_to new_session_url
    invitee = User.find_by(email_address: "invitee@example.com")
    assert invitee.account.present?, "bootstraps its own account"
    assert_not_equal invitation.account, invitee.account
    assert invitation.reload.pending?, "the invite stays open for a later fold-in"
  end

  test "a signup arriving via the invite link is never interrupted" do
    invitation = issue_invitation
    get accept_invitation_url(token: invitation.token)     # stores the token in session
    assert_difference "User.count", 1 do
      post registration_url, params: { user: {
        email_address: "invitee@example.com", password: "password123", password_confirmation: "password123" } }
    end
    assert_redirected_to new_session_url
    assert_nil User.find_by(email_address: "invitee@example.com").account, "joins at first sign-in, no bootstrap"
  end

  test "the registration form pre-fills the invited email when arriving via the invite link" do
    invitation = issue_invitation("bia@example.com")
    get accept_invitation_url(token: invitation.token)
    get new_registration_url
    assert_response :success
    assert_select "input[name='user[email_address]'][value=?]", "bia@example.com"
  end
end
