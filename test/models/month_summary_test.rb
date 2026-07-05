require "test_helper"

class MonthSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(user: @user, institution: @inst, balance_cents: 100_000)
    @card    = CreditCard.create!(user: @user, institution: @inst, bill_due_day: 10, closing_offset_days: 7)
    @month   = Date.new(2026, 7, 1)
  end

  def summary(month = @month) = MonthSummary.new(@user, month)

  def post!(**attrs)
    @user.transactions.create!({ amount_cents: 1_000, occurred_on: Date.new(2026, 7, 15),
                                 status: "posted", direction: "expense" }.merge(attrs))
  end

  test "saídas counts posted bank expenses; card spend settles through the fatura, not saídas" do
    post!(bank_account: @account, amount_cents: 5_000)
    post!(credit_card: @card, amount_cents: 9_000, occurred_on: Date.new(2026, 6, 20)) # d10/f7 → July fatura
    s = summary
    assert_equal 5_000, s.saidas_cents
    assert_equal 9_000, s.faturas_cents
  end

  test "entradas counts posted incomes; a card income (estorno) does not" do
    post!(bank_account: @account, direction: "income", amount_cents: 4_500_00)
    post!(credit_card: @card, direction: "income", amount_cents: 3_000, occurred_on: Date.new(2026, 6, 20))
    assert_equal 4_500_00, summary.entradas_cents
  end

  test "remaining = entradas − saídas − faturas − guardado" do
    post!(bank_account: @account, direction: "income", amount_cents: 10_000)
    post!(bank_account: @account, direction: "expense", amount_cents: 3_000)
    post!(credit_card: @card, direction: "expense", amount_cents: 2_000, occurred_on: Date.new(2026, 6, 20))
    assert_equal 10_000 - 3_000 - 2_000, summary.remaining_cents
  end

  test "derived account balance = anchor + signed posted rows created after the anchor" do
    @account.update!(balance_cents: 100_000) # stamps balance_anchored_at = now
    post!(bank_account: @account, direction: "expense", amount_cents: 3_000)
    post!(bank_account: @account, direction: "income", amount_cents: 5_000)
    assert_equal 100_000 - 3_000 + 5_000, summary.account_balances[@account.id]
  end

  test "mode is past/current/future relative to the SP month" do
    today = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month
    assert_equal :current, summary(today).mode
    assert_equal :past,    summary(today << 1).mode
    assert_equal :future,  summary(today >> 1).mode
  end

  test "an unassigned posted expense counts in saídas until it gets an instrument" do
    post!(amount_cents: 7_000) # no instrument
    assert_equal 7_000, summary.saidas_cents
  end

  # Adversarial hub-constancy (06 §6.5.2): a checking→checking transfer moves exactly the two
  # per-account balances and changes NO other headline.
  test "a checking→checking transfer changes only the two balances" do
    a = BankAccount.create!(user: @user, institution: @inst, balance_cents: 100_000)
    b = BankAccount.create!(user: @user, institution: @inst, balance_cents: 50_000)
    headlines = ->(s) { [ s.entradas_cents, s.saidas_cents, s.faturas_cents, s.a_pagar_cents,
                          s.guardado_cents, s.remaining_cents ] }
    before = headlines.call(MonthSummary.new(@user, @month))

    @user.transactions.create!(direction: "transfer", status: "posted", amount_cents: 20_000,
                               occurred_on: Date.new(2026, 7, 10), bank_account: a, transfer_to_bank_account: b)

    after = MonthSummary.new(@user, @month)
    assert_equal before, headlines.call(after)               # no headline moved
    assert_equal 100_000 - 20_000, after.account_balances[a.id]
    assert_equal 50_000 + 20_000, after.account_balances[b.id]
  end

  test "expected income counts once: a linked posted receipt suppresses the expected term" do
    month = Date.current.beginning_of_month
    inc = Income.create!(user: @user, bank_account: @account, name: "salário", amount_cents: 500_000,
                         schedule_kind: "fixed_day", schedule_day: 5)
    assert_equal 500_000, MonthSummary.new(@user, month).entradas_cents # expected term only
    @user.transactions.create!(direction: "income", status: "posted", amount_cents: 500_000,
                               occurred_on: Date.current, bank_account: @account, income: inc)
    assert_equal 500_000, MonthSummary.new(@user, month).entradas_cents # posted, not doubled
  end

  test "an UNLINKED deposit within ±10% on the income's account also suppresses the expected term" do
    month = Date.current.beginning_of_month
    Income.create!(user: @user, bank_account: @account, name: "salário", amount_cents: 500_000,
                   schedule_kind: "fixed_day", schedule_day: 5)
    @user.transactions.create!(direction: "income", status: "posted", amount_cents: 480_000, # income_id nil, within 10%
                               occurred_on: Date.current, bank_account: @account)
    assert_equal 480_000, MonthSummary.new(@user, month).entradas_cents # posted only, expected suppressed
  end

  test "guardado counts transfers into a savings account, keyed by billing_month" do
    checking = BankAccount.create!(user: @user, institution: @inst, balance_cents: 100_000)
    savings  = BankAccount.create!(user: @user, institution: @inst, kind: "savings")
    @user.transactions.create!(direction: "transfer", status: "posted", amount_cents: 30_000,
                               occurred_on: Date.new(2026, 7, 5), bank_account: checking, transfer_to_bank_account: savings)
    assert_equal 30_000, summary.guardado_cents
    assert_equal(-30_000, summary.remaining_cents) # entradas 0 − saídas 0 − faturas 0 − guardado 30k
  end
end
