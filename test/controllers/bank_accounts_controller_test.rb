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
    assert_response :unprocessable_entity   # streams the form errors; form is not reset
  end

  test "edit renders the form for the user's account" do
    account = @user.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    get edit_bank_account_url(account)
    assert_response :success
    assert_select "form#bank_account_form"
  end

  test "update changes attributes and redirects" do
    account = @user.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    patch bank_account_url(account),
          params: { bank_account: { nickname: "Conta principal", kind: "investment", balance_reais: "2.500,00" } }
    assert_redirected_to bank_accounts_url
    account.reload
    assert_equal "Conta principal", account.nickname
    assert_equal "investment", account.kind
    assert_equal 250000, account.balance_cents
  end

  test "update with an invalid kind re-renders" do
    account = @user.bank_accounts.create!(institution: @nubank)
    patch bank_account_url(account), params: { bank_account: { kind: "bogus" } }
    assert_response :unprocessable_entity
    assert_equal "checking", account.reload.kind
  end

  test "cannot edit or update another user's account" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    account = other.bank_accounts.create!(institution: @nubank, nickname: "Alheia")
    get edit_bank_account_url(account)
    assert_response :not_found
    patch bank_account_url(account), params: { bank_account: { nickname: "hijack" } }
    assert_response :not_found
    assert_equal "Alheia", account.reload.nickname
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
