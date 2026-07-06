require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst = Institution.find_by(code: "260")
    @checking = @user.account.bank_accounts.create!(institution: @inst, nickname: "Itaú", balance_cents: 100_000)
    @savings  = @user.account.bank_accounts.create!(institution: @inst, nickname: "Caixinha", kind: "savings", balance_cents: 0)
  end

  def transfer!(from:, to:, amount: "300", on: Date.current)
    post transfers_url(month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transfer: { amount_reais: amount, bank_account_id: from.id,
                               transfer_to_bank_account_id: to.id, occurred_on: on.to_s } }
  end

  test "creates exactly one posted transfer row" do
    assert_difference -> { @user.account.transactions.where(direction: "transfer").count }, 1 do
      transfer!(from: @checking, to: @savings, amount: "300,00")
    end
    t = @user.account.transactions.where(direction: "transfer").sole
    assert_equal 30_000, t.amount_cents
    assert t.posted?
    assert_nil t.credit_card_id
  end

  test "source = destination is rejected (keyed same_account error), no row created" do
    transfer!(from: @checking, to: @checking, amount: "50")
    assert_response :unprocessable_entity
    assert_equal 0, @user.account.transactions.where(direction: "transfer").count
  end

  test "a transfer to savings bumps Guardado; a same-month resgate does NOT decrement it (gross)" do
    transfer!(from: @checking, to: @savings, amount: "200")
    assert_equal 20_000, MonthSummary.new(@user.account, Date.current.beginning_of_month).guardado_cents
    transfer!(from: @savings, to: @checking, amount: "50") # resgate
    assert_equal 20_000, MonthSummary.new(@user.account, Date.current.beginning_of_month).guardado_cents
  end

  test "the hero Save CTA appears only with a surplus and a savings account" do
    @user.account.transactions.create!(amount_cents: 500_00, occurred_on: Date.current, status: "posted",
                               direction: "income", bank_account: @checking)
    get transactions_url
    assert_select "a", text: I18n.t("transactions.hero.save_cta", locale: :"pt-BR")
  end
end
