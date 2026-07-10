require "test_helper"

# invitations#create was the app's only zero-coverage mutation (07-coverage-audit.md §MU): the
# happy owner path + the owner gate (MU-01/03 request-layer). Revoke is exercised via the flow.
class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:confirmed)
    @owner.update!(name: "Owner", phone: "5511912345678", onboarded_at: Time.current)
    @account = @owner.account
    @member  = User.create!(email_address: "member@example.com", password: "password123", name: "Bia")
    @account.memberships.create!(user: @member, role: "member")
  end

  test "an owner creates an invitation and the invite email is queued" do
    sign_in_as(@owner)
    assert_enqueued_emails 1 do
      assert_difference -> { @account.invitations.pending.count }, 1 do
        post account_invitations_url, params: { invitation: { email: "novo@example.com" } }, as: :turbo_stream
      end
    end
    assert_response :success
    assert @account.invitations.pending.exists?(email: "novo@example.com")
  end

  test "an invalid email re-renders the form with errors and creates nothing" do
    sign_in_as(@owner)
    assert_no_difference -> { Invitation.count } do
      post account_invitations_url, params: { invitation: { email: "not-an-email" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "a non-owner cannot create an invitation" do
    sign_in_as(@member)
    assert_no_difference -> { Invitation.count } do
      post account_invitations_url, params: { invitation: { email: "novo@example.com" } }
    end
    assert_redirected_to account_path
    assert_equal I18n.t("accounts.not_owner"), flash[:alert]
  end
end
