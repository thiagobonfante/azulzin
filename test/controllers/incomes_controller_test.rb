require "test_helper"

class IncomesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @account = @user.bank_accounts.create!(institution: Institution.find_by(code: "260"))
  end

  def create_income(**params)
    post incomes_url, as: :turbo_stream, params: { income: {
      name: "salário", amount_reais: "4.500", bank_account_id: @account.id,
      schedule_kind: "fixed_day", schedule_day: 5 }.merge(params) }
  end

  test "index renders the management page and the add form" do
    get incomes_url
    assert_response :success
    assert_select "form#income_form"
  end

  test "creates an income (nth business day ≤ 10, appended)" do
    assert_difference -> { @user.incomes.count }, 1 do
      create_income(schedule_kind: "nth_business_day", schedule_day: 3)
    end
    assert_response :success
  end

  test "nth_business_day with day 15 is rejected with a 422" do
    create_income(schedule_kind: "nth_business_day", schedule_day: 15)
    assert_response :unprocessable_entity
    assert_equal 0, @user.incomes.count
  end

  test "a forged bank_account_id of another user is rejected, no leak" do
    other  = User.create!(email_address: "x@example.com", password: "password123")
    theirs = other.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    create_income(bank_account_id: theirs.id)
    assert_response :unprocessable_entity
    assert_equal 0, @user.incomes.count
  end

  test "the hub prompt appears with zero incomes and disappears once one exists" do
    get transactions_url
    assert_select "a", text: I18n.t("transactions.hub.add_incomes_prompt", locale: :"pt-BR")
    @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                          schedule_kind: "fixed_day", schedule_day: 5)
    get transactions_url
    assert_select "a", text: I18n.t("transactions.hub.add_incomes_prompt", locale: :"pt-BR"), count: 0
  end

  test "edit renders the form for the user's income" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    get edit_income_url(inc)
    assert_response :success
    assert_select "form#income_form"
  end

  test "update changes attributes and redirects" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    patch income_url(inc), params: { income: {
      name: "aluguel", amount_reais: "1.200", bank_account_id: @account.id,
      schedule_kind: "nth_business_day", schedule_day: 3 } }
    assert_redirected_to incomes_url
    inc.reload
    assert_equal "aluguel", inc.name
    assert_equal 120_000, inc.amount_cents
    assert_equal "nth_business_day", inc.schedule_kind
    assert_equal 3, inc.schedule_day
  end

  test "update with an invalid schedule day re-renders" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    patch income_url(inc), params: { income: { schedule_kind: "nth_business_day", schedule_day: 15 } }
    assert_response :unprocessable_entity
    assert_equal 5, inc.reload.schedule_day
  end

  test "update rejects a forged bank_account_id of another user" do
    other  = User.create!(email_address: "y@example.com", password: "password123")
    theirs = other.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    patch income_url(inc), params: { income: { bank_account_id: theirs.id } }
    assert_response :unprocessable_entity
    assert_equal @account.id, inc.reload.bank_account_id
  end

  test "cannot edit or update another user's income" do
    other  = User.create!(email_address: "z@example.com", password: "password123")
    theirs = other.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    inc = other.incomes.create!(bank_account: theirs, name: "alheia", amount_cents: 100,
                                schedule_kind: "fixed_day", schedule_day: 5)
    get edit_income_url(inc)
    assert_response :not_found
    patch income_url(inc), params: { income: { name: "hijack" } }
    assert_response :not_found
    assert_equal "alheia", inc.reload.name
  end

  test "destroy removes the income" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    assert_difference -> { @user.incomes.count }, -1 do
      delete income_url(inc), as: :turbo_stream
    end
  end

  test "receive posts a linked deposit for the month, once" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    month = Date.current.beginning_of_month
    assert_difference -> { @user.transactions.posted.count }, 1 do
      patch receive_income_url(inc, month: month.strftime("%Y-%m")), as: :turbo_stream
    end
    receipt = inc.receipts.posted.last
    assert_equal 450_000, receipt.amount_cents
    assert_equal @account.id, receipt.bank_account_id
    assert_equal month, receipt.billing_month
    assert inc.received_in?(month)

    # Counts-once: a second click never double-posts.
    assert_no_difference -> { @user.transactions.posted.count } do
      patch receive_income_url(inc, month: month.strftime("%Y-%m")), as: :turbo_stream
    end
  end

  test "cannot receive another user's income" do
    other  = User.create!(email_address: "y@example.com", password: "password123")
    theirs = other.incomes.create!(bank_account: other.bank_accounts.create!(institution: Institution.find_by(code: "260")),
                                   name: "alheia", amount_cents: 100, schedule_kind: "fixed_day", schedule_day: 5)
    patch receive_income_url(theirs), as: :turbo_stream
    assert_response :not_found
  end
end
