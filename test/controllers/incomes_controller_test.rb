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

  test "destroy removes the income" do
    inc = @user.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                                schedule_kind: "fixed_day", schedule_day: 5)
    assert_difference -> { @user.incomes.count }, -1 do
      delete income_url(inc), as: :turbo_stream
    end
  end
end
