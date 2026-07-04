require "test_helper"

class BankAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @nubank = Institution.find_by(code: "260")
  end

  test "index requires a completed onboarding" do
    @user.update!(onboarded_at: nil)
    get bank_accounts_url
    assert_redirected_to onboarding_url
  end

  test "index lists the user's accounts" do
    @user.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    get bank_accounts_url
    assert_response :success
    assert_select "#bank_accounts_list"
  end

  test "create adds an account with parsed money (turbo stream)" do
    assert_difference -> { @user.bank_accounts.count }, 1 do
      post bank_accounts_url, as: :turbo_stream,
           params: { bank_account: { institution_id: @nubank.id, nickname: "Salário", balance_reais: "1.200,50" } }
    end
    assert_response :success
    assert_equal 120050, @user.bank_accounts.last.balance_cents
  end

  test "create without an institution does not persist" do
    assert_no_difference -> { @user.bank_accounts.count } do
      post bank_accounts_url, as: :turbo_stream, params: { bank_account: { nickname: "x" } }
    end
    assert_response :success   # re-renders the form with errors
  end

  test "destroy removes the account" do
    account = @user.bank_accounts.create!(institution: @nubank)
    assert_difference -> { @user.bank_accounts.count }, -1 do
      delete bank_account_url(account), as: :turbo_stream
    end
  end

  test "cannot destroy another user's account" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    account = other.bank_accounts.create!(institution: @nubank)
    delete bank_account_url(account), as: :turbo_stream
    assert_response :not_found
    assert other.bank_accounts.exists?(account.id)
  end
end
