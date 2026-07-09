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
    @user.account.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    get bank_accounts_url
    assert_response :success
    assert_select "#bank_accounts_list"
  end

  test "create adds an account with parsed money (turbo stream)" do
    assert_difference -> { @user.account.bank_accounts.count }, 1 do
      post bank_accounts_url, as: :turbo_stream,
           params: { bank_account: { institution_id: @nubank.id, nickname: "Salário", balance_reais: "1.200,50" } }
    end
    assert_response :success
    assert_equal 120050, @user.account.bank_accounts.last.balance_cents
  end

  test "create with a blank balance starts at zero and counts later movements" do
    post bank_accounts_url, as: :turbo_stream,
         params: { bank_account: { institution_id: @nubank.id, nickname: "Caixinha", kind: "savings" } }
    acct = @user.account.bank_accounts.last
    assert_equal 0, acct.balance_cents
    assert acct.balance_informed?

    @user.account.transactions.create!(bank_account: @user.account.bank_accounts.create!(institution: @nubank),
                                       direction: "transfer", status: "posted", amount_cents: 500_000,
                                       occurred_on: Date.current, transfer_to_bank_account_id: acct.id)
    assert_equal 500_000, acct.derived_balance_cents
  end

  # ── Round 3 decision 7: livre / guardado-para-meta split ───────────────────────────────

  test "a caixinha backing an active goal shows the livre/reservado split, mirroring Progress" do
    account  = @user.account
    checking = account.bank_accounts.create!(institution: @nubank, kind: "checking", balance_cents: 0)
    caixinha = account.bank_accounts.create!(institution: @nubank, kind: "savings", balance_cents: 800_000)
    other    = account.bank_accounts.create!(institution: @nubank, kind: "savings", balance_cents: 100_000)
    month    = Date.current.beginning_of_month

    goal = account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                                 target_date: month >> 17, status: "active",
                                 monthly_target_cents: 300_000, starts_on: month,
                                 bank_account: caixinha,
                                 initial_saved_cents: 400_000, initial_saved_bank_account: caixinha)
    account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 100_000,
                                 bank_account: checking, transfer_to_bank_account: caixinha,
                                 occurred_on: Date.current)

    # The invariant: the per-account earmark attribution sums to exactly what Progress shows.
    assert_equal 500_000, Goals::Progress.new(goal).actual_cents

    get bank_accounts_url
    assert_response :success
    assert_match I18n.t("bank_accounts.reserved_for_goal", amount: brl_pt(500_000)), @response.body
    assert_match I18n.t("bank_accounts.free_balance", amount: brl_pt(400_000)), @response.body   # 900_000 derived − 500_000
    # The goal-less caixinha (`other`) stays a single figure — exactly one reserved line on the page.
    assert_equal 1, @response.body.scan(I18n.t("bank_accounts.reserved_for_goal", amount: "").strip).size
    assert other.reload.balance_informed?
  end

  test "a draft goal reserves nothing" do
    account  = @user.account
    caixinha = account.bank_accounts.create!(institution: @nubank, kind: "savings", balance_cents: 500_000)
    account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                          target_date: Date.current.beginning_of_month >> 17, status: "draft",
                          initial_saved_cents: 400_000, initial_saved_bank_account: caixinha)
    get bank_accounts_url
    refute_match I18n.t("bank_accounts.reserved_for_goal", amount: "").strip, @response.body
  end

  def brl_pt(cents) = I18n.with_locale(:"pt-BR") { ActionController::Base.helpers.number_to_currency(BigDecimal(cents) / 100, unit: "R$") }

  test "create without an institution does not persist" do
    assert_no_difference -> { @user.account.bank_accounts.count } do
      post bank_accounts_url, as: :turbo_stream, params: { bank_account: { nickname: "x" } }
    end
    assert_response :unprocessable_entity   # streams the form errors; form is not reset
  end

  test "edit renders the form for the user's account" do
    account = @user.account.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    get edit_bank_account_url(account)
    assert_response :success
    assert_select "form#bank_account_form"
  end

  test "update changes attributes and redirects" do
    account = @user.account.bank_accounts.create!(institution: @nubank, nickname: "Salário")
    patch bank_account_url(account),
          params: { bank_account: { nickname: "Conta principal", kind: "investment", balance_reais: "2.500,00" } }
    assert_redirected_to bank_accounts_url
    account.reload
    assert_equal "Conta principal", account.nickname
    assert_equal "investment", account.kind
    assert_equal 250000, account.balance_cents
  end

  test "update with an invalid kind re-renders" do
    account = @user.account.bank_accounts.create!(institution: @nubank)
    patch bank_account_url(account), params: { bank_account: { kind: "bogus" } }
    assert_response :unprocessable_entity
    assert_equal "checking", account.reload.kind
  end

  test "cannot edit or update another user's account" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    account = other.account.bank_accounts.create!(institution: @nubank, nickname: "Alheia")
    get edit_bank_account_url(account)
    assert_response :not_found
    patch bank_account_url(account), params: { bank_account: { nickname: "hijack" } }
    assert_response :not_found
    assert_equal "Alheia", account.reload.nickname
  end

  test "destroy soft-deletes the account (leaves the kept list, row survives)" do
    account = @user.account.bank_accounts.create!(institution: @nubank)
    assert_difference -> { @user.account.bank_accounts.kept.count }, -1 do
      delete bank_account_url(account), as: :turbo_stream
    end
    assert account.reload.soft_deleted?
    assert BankAccount.exists?(account.id)
  end

  test "cannot destroy another user's account" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    account = other.account.bank_accounts.create!(institution: @nubank)
    delete bank_account_url(account), as: :turbo_stream
    assert_response :not_found
    assert other.account.bank_accounts.exists?(account.id)
  end
end
