require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:confirmed)
    @owner.update!(name: "Owner", onboarded_at: Time.current)
    @account = @owner.account
    @invitation = Invitation.issue!(account: @account, email: "invitee@example.com", invited_by: @owner)
  end

  test "logged-out GET renders the landing page and stores the token in session" do
    get accept_invitation_url(token: @invitation.token)
    assert_response :success
    assert_equal @invitation.token, session[:invitation_token]
  end

  test "an unknown/expired token redirects to sign-in generically" do
    get accept_invitation_url(token: "does-not-exist")
    assert_redirected_to new_session_path
  end

  test "a signed-in GET changes NOTHING (no auto-accept on GET — CSRF/tenant-capture guard)" do
    invitee = User.create!(email_address: "invitee@example.com", password: "password123")
    Accounts::Bootstrap.call(invitee)
    sign_in_as(invitee)
    assert_no_difference -> { @account.memberships.count } do
      get accept_invitation_url(token: @invitation.token)
    end
    assert_response :success
    assert @invitation.reload.pending?
  end

  test "the confirm POST folds in a signed-in solo+empty user" do
    invitee = User.create!(email_address: "invitee@example.com", password: "password123")
    Accounts::Bootstrap.call(invitee)
    sign_in_as(invitee)
    assert_difference -> { @account.memberships.count }, 1 do
      post confirm_invitation_url(token: @invitation.token)
    end
    assert @invitation.reload.accepted_at
    assert_redirected_to dashboard_path
  end

  test "path (a): invite → password signup (different email) → verification click → member, no orphan account" do
    get accept_invitation_url(token: @invitation.token)   # stores the token
    assert_difference -> { User.count }, 1 do
      post registration_url, params: { user: { email_address: "newbie@example.com",
        password: "password123", password_confirmation: "password123" } }
    end
    newbie = User.find_by(email_address: "newbie@example.com")
    assert_nil newbie.account, "an invited signup does not bootstrap its own account"

    get email_verification_url(newbie.generate_token_for(:email_verification))   # = first sign-in
    assert_redirected_to root_path
    assert_equal @account, newbie.reload.account
    assert newbie.account_membership.member?
    assert @invitation.reload.accepted_at
    assert_equal 1, @account.memberships.where(user: newbie).count, "exactly one membership, no orphan account"
  end

  test "an invited signup joins even when the confirmation click comes after the session TTL" do
    get accept_invitation_url(token: @invitation.token)
    post registration_url, params: { user: { email_address: "late@example.com",
      password: "password123", password_confirmation: "password123" } }
    late = User.find_by(email_address: "late@example.com")
    assert_equal @invitation.token, late.pending_invitation_token, "invite persisted on the user at signup"
    travel 31.minutes do
      get email_verification_url(late.generate_token_for(:email_verification))
    end
    assert_equal @account, late.reload.account, "the persisted token outlives the session copy"
    assert @invitation.reload.accepted_at
    assert_nil late.pending_invitation_token, "single-shot: consumed at first sign-in"
  end

  test "an invited signup joins even when the confirmation click happens in another browser" do
    get accept_invitation_url(token: @invitation.token)
    post registration_url, params: { user: { email_address: "mobile@example.com",
      password: "password123", password_confirmation: "password123" } }
    mobile = User.find_by(email_address: "mobile@example.com")

    other_browser = open_session   # no cookies: the invite token is NOT in this session
    other_browser.get email_verification_url(mobile.generate_token_for(:email_verification))
    assert_equal @account, mobile.reload.account, "joined via the token persisted at signup"
    assert @invitation.reload.accepted_at
  end

  test "a session token older than 30 minutes is still ignored for an existing user's sign-in" do
    existing = User.create!(email_address: "existing@example.com", password: "password123",
                            confirmed_at: Time.current)
    Accounts::Bootstrap.call(existing)
    existing.account.bank_accounts.create!(institution: Institution.find_by(code: "260"))  # not solo+empty
    get accept_invitation_url(token: @invitation.token)   # stores the token, then the user walks away
    travel 31.minutes do
      post session_url, params: { email_address: "existing@example.com", password: "password123" }
    end
    assert @invitation.reload.pending?, "a stale session token never drives a join"
    assert_not_equal @account, existing.reload.account
  end
end
