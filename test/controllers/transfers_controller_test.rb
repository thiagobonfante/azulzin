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
    # The user sees the translated attribute + message, never a "Translation missing" leak.
    assert_match "Conta de destino não pode ser a mesma conta de origem.", response.body
    assert_no_match(/[Tt]ranslation missing/, response.body)
  end

  test "a transfer to savings bumps Guardado; a same-month resgate does NOT decrement it (gross)" do
    transfer!(from: @checking, to: @savings, amount: "200")
    assert_equal 20_000, MonthSummary.new(@user.account, Date.current.beginning_of_month).saved_cents
    transfer!(from: @savings, to: @checking, amount: "50") # resgate
    assert_equal 20_000, MonthSummary.new(@user.account, Date.current.beginning_of_month).saved_cents
  end

  test "the hero save-money CTA (sobra button + modal) appears only with a surplus and a savings account" do
    @user.account.transactions.create!(amount_cents: 500_00, occurred_on: Date.current, status: "posted",
                               direction: "income", bank_account: @checking)
    get transactions_url
    assert_select "section#hero[data-controller=?]", "surplus-cta"
    assert_select "#save_money_form"
  end

  test "modal batch creates one transfer per filled source, skipping blanks" do
    other = @user.account.bank_accounts.create!(institution: @inst, nickname: "Nu", balance_cents: 50_000)
    assert_difference -> { @user.account.transactions.where(direction: "transfer").count }, 2 do
      post transfers_url(month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
           params: { transfer: { transfer_to_bank_account_id: @savings.id, occurred_on: Date.current.to_s },
                     sources: { @checking.id.to_s => "100,00", other.id.to_s => "50", @savings.id.to_s => "" } }
    end
    assert_response :ok
    assert_equal [ 5_000, 10_000 ],
                 @user.account.transactions.where(direction: "transfer").pluck(:amount_cents).sort
  end

  test "modal batch is all-or-nothing: one invalid source rolls back the rest" do
    assert_no_difference -> { @user.account.transactions.where(direction: "transfer").count } do
      post transfers_url(month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
           params: { transfer: { transfer_to_bank_account_id: @savings.id, occurred_on: Date.current.to_s },
                     sources: { @checking.id.to_s => "100", @savings.id.to_s => "50" } } # savings→savings
    end
    assert_response :unprocessable_entity
  end

  # ── Round 3 P3: goal boost tie-in ──────────────────────────────────────────────────────

  def active_goal!(savings_account, kind: "purchase")
    @user.account.goals.create!(name: "Carro", kind: kind, target_cents: 6_000_000,
                                target_date: (kind == "purchase" ? Date.new(2027, 12, 1) : nil),
                                status: "active", monthly_target_cents: 300_000,
                                starts_on: Date.current.beginning_of_month, bank_account: savings_account)
  end

  test "a transfer into a goal's savings account streams the boost toast with the fresh forecast" do
    goal = active_goal!(@savings)
    transfer!(from: @checking, to: @savings, amount: "300,00")
    assert_response :ok
    projected = Goals::Progress.new(goal.reload).projected_done_on
    assert_match I18n.t("transfers.saved_goal_boost", goal: goal.name,
                        month: I18n.l(projected, format: :month_year)), @response.body
    assert_match goal_path(goal), @response.body
  end

  test "a savings_rate goal gets the 'conta pra meta' framing instead of a forecast" do
    goal = active_goal!(@savings, kind: "savings_rate")
    transfer!(from: @checking, to: @savings, amount: "50")
    assert_match I18n.t("transfers.saved_goal_boost_savings", goal: goal.name), @response.body
  end

  test "a savings transfer with no goal on that savings account keeps only the plain celebration" do
    transfer!(from: @checking, to: @savings, amount: "50")
    assert_response :ok
    refute_match "Nova previsão", @response.body
  end

  test "the save-money modal defaults its destination to the active goal's caixinha" do
    other = @user.account.bank_accounts.create!(institution: @inst, nickname: "Nova caixinha",
                                                kind: "savings", balance_cents: 0)
    active_goal!(other)   # not the first-created savings account
    @user.account.transactions.create!(amount_cents: 500_00, occurred_on: Date.current, status: "posted",
                                       direction: "income", bank_account: @checking)
    get transactions_url
    assert_select "#save_money_form select[name='transfer[transfer_to_bank_account_id]'] option[value='#{other.id}'][selected]"
  end

  test "modal batch with no amounts filled creates nothing and 422s" do
    assert_no_difference -> { @user.account.transactions.where(direction: "transfer").count } do
      post transfers_url(month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
           params: { transfer: { transfer_to_bank_account_id: @savings.id, occurred_on: Date.current.to_s },
                     sources: { @checking.id.to_s => "" } }
    end
    assert_response :unprocessable_entity
  end
end
