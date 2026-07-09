require "test_helper"

# Budgets::Check with the goals extension (.plans/goals 06 §3): a goal trim temporarily tightens
# the standing budget through the SAME check; the binding limit names the meta.
class Budgets::CheckTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  JULY = Date.new(2026, 7, 1)

  setup do
    @user     = users(:confirmed)
    @account  = @user.account
    @inst     = Institution.find_by(code: "260")
    @bank     = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    @rest     = @account.categories.create!(name: "Restaurantes")
    travel_to Time.utc(2026, 7, 20, 12)
  end

  teardown { travel_back }

  def spend!(cents) = @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                                    category: @rest, bank_account: @bank, occurred_on: JULY, billing_month: JULY)

  def goal_with_cut(cap:)
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000, target_date: Date.new(2027, 12, 1),
                           status: "active", monthly_target_cents: 300_000, starts_on: JULY, activated_at: Time.utc(2026, 7, 1),
                           bank_account: @caixinha, baseline: { "median_income_cents" => 0, "categories" => [] },
                           plan: { "cuts" => [ { "category_id" => @rest.id, "cap_cents" => cap, "baseline_cents" => 60_000 } ] })
  end

  def check = Budgets::Check.call(@account, month: JULY, warn_percent: 80, breach_percent: 100)

  test "with no goal and a standing budget, behaves exactly as before" do
    @rest.update!(monthly_budget_cents: 60_000)
    spend!(61_000)   # over 100%
    event = check.first
    assert_equal "budget_breach", event[:kind]
    assert_equal 60_000, event[:payload][:budget_cents]
    assert_nil event[:payload][:goal_name]
  end

  test "a goal trim tighter than the standing budget binds and names the meta" do
    @rest.update!(monthly_budget_cents: 60_000)
    goal_with_cut(cap: 40_000)
    spend!(45_000)   # under the 60k budget but over the 40k trim
    event = check.first
    assert_equal "budget_breach", event[:kind]
    assert_equal 40_000, event[:payload][:budget_cents]
    assert_equal "Carro", event[:payload][:goal_name]
  end

  test "a goal trim on an unbudgeted category still fires (the trim alone binds)" do
    goal_with_cut(cap: 40_000)         # no monthly_budget_cents on the category
    spend!(45_000)
    event = check.first
    assert_equal "budget_breach", event[:kind]
    assert_equal "Carro", event[:payload][:goal_name]
  end

  test "a goal starting NEXT month does not tighten this month's alerts (month-aware trims)" do
    @rest.update!(monthly_budget_cents: 60_000)
    goal_with_cut(cap: 40_000).update!(starts_on: Date.new(2026, 8, 1))
    spend!(45_000)                     # over the 40k trim, but the trim isn't in force in July
    assert_empty check
  end

  test "when the standing budget is tighter, it binds and the meta is not named" do
    @rest.update!(monthly_budget_cents: 30_000)
    goal_with_cut(cap: 40_000)
    spend!(31_000)                     # over the 30k budget, under the 40k trim
    event = check.first
    assert_equal "budget_breach", event[:kind]
    assert_equal 30_000, event[:payload][:budget_cents]
    assert_nil event[:payload][:goal_name]
  end
end
