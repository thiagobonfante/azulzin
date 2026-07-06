require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:confirmed)
    @owner.update!(name: "Owner", phone: "5511912345678", onboarded_at: Time.current)
    @account = @owner.account
    @member_user = User.create!(email_address: "member@example.com", password: "password123",
                                name: "Bia", onboarded_at: Time.current)
    @account.memberships.create!(user: @member_user, role: "member")
  end

  test "show renders for any member" do
    sign_in_as(@member_user)
    get account_url
    assert_response :success
  end

  test "owner renames the account" do
    sign_in_as(@owner)
    patch account_url, params: { account: { name: "Família Bonfante" } }
    assert_equal "Família Bonfante", @account.reload.name
    assert_redirected_to account_path
  end

  test "a non-owner cannot rename or delete (require_owner! redirect, no change)" do
    sign_in_as(@member_user)
    patch account_url, params: { account: { name: "Hacked" } }
    assert_not_equal "Hacked", @account.reload.name
    assert_redirected_to account_path
    assert_no_difference -> { Account.count } do
      delete account_url
    end
  end

  test "account deletion signs out EVERY member and cascades the financial data" do
    member_session = @member_user.sessions.create!
    bank = @account.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    sign_in_as(@owner)
    assert_difference -> { Account.count }, -1 do
      delete account_url
    end
    assert_not Session.exists?(member_session.id), "the co-member's live session is terminated"
    assert_not BankAccount.exists?(bank.id), "financial data cascaded off the account"
    assert_redirected_to new_session_path
  end
end
