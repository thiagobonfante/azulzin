require "test_helper"

class IncomeTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @account = BankAccount.create!(user: @user, institution: Institution.find_by(code: "260"))
  end

  def build(**attrs)
    Income.new({ user: @user, bank_account: @account, name: "salário", amount_cents: 450_000,
                 schedule_kind: "fixed_day", schedule_day: 5 }.merge(attrs))
  end

  test "a well-formed income is valid" do
    assert build.valid?, build.errors.full_messages.to_sentence
  end

  test "amount must be positive" do
    assert_not build(amount_cents: 0).valid?
  end

  test "fixed_day schedule_day is 1..31" do
    assert build(schedule_day: 31).valid?
    assert_not build(schedule_day: 32).valid?
  end

  test "nth_business_day schedule_day is 1..10" do
    assert build(schedule_kind: "nth_business_day", schedule_day: 10).valid?
    assert_not build(schedule_kind: "nth_business_day", schedule_day: 11).valid?
  end

  test "expected_on resolves through Recurrence" do
    assert_equal Date.new(2026, 7, 5), build.expected_on(Date.new(2026, 7, 1))
  end

  test "received_in? becomes true once a posted receipt lands in the month" do
    inc = build; inc.save!
    assert_not inc.received_in?(Date.new(2026, 7, 1))
    Transaction.create!(user: @user, bank_account: @account, income: inc, direction: "income",
                        status: "posted", amount_cents: 450_000, occurred_on: Date.new(2026, 7, 5))
    assert inc.received_in?(Date.new(2026, 7, 1))
  end
end
