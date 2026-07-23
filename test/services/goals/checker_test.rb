require "test_helper"

# The weekly guardian's status ladder (.plans/goals 03 §3): pace, large-purchase, grace, and the
# irregular-income guard. Pure Postgres, no LLM.
class Goals::CheckerTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @savings_account = @account.bank_accounts.create!(institution: @inst, kind: "savings")
  end

  teardown { travel_back }

  def active_goal(monthly: 300_000, baseline: {})
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                           target_date: Date.new(2027, 12, 1), status: "active",
                           monthly_target_cents: monthly, starts_on: Date.new(2026, 7, 1),
                           activated_at: Time.utc(2026, 7, 1), bank_account: @savings_account,
                           baseline: { "median_income_cents" => 0, "categories" => [] }.merge(baseline))
  end

  def save!(cents, month: Date.new(2026, 7, 1))
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @savings_account,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  def spend!(cents, category:, on:)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                  category:, bank_account: @checking, occurred_on: on, billing_month: on.beginning_of_month)
  end

  test "on the full monthly contribution → on_track" do
    travel_to Time.utc(2026, 7, 31, 12)
    g = active_goal
    save!(300_000)
    assert_equal "on_track", Goals::Checker.call(g).status
  end

  test "moderately behind → at_risk with a pace finding" do
    travel_to Time.utc(2026, 7, 31, 12)
    g = active_goal
    save!(250_000)   # 83% of the 300_000 expected → below 95%, above 80%
    result = Goals::Checker.call(g)
    assert_equal "at_risk", result.status
    assert_equal "pace", result.findings.first["finding"]
  end

  test "far behind → off_track" do
    travel_to Time.utc(2026, 7, 31, 12)
    g = active_goal   # nothing saved → 0% of expected
    assert_equal "off_track", Goals::Checker.call(g).status
  end

  test "within the 2-week activation grace → on_track, no findings" do
    travel_to Time.utc(2026, 7, 10, 12)   # activated Jul 1, still in grace
    g = active_goal
    assert_equal "on_track", Goals::Checker.call(g).status
    assert_empty Goals::Checker.call(g).findings
  end

  test "the pre-start gap month never alerts — grace extends to starts_on (round 3)" do
    travel_to Time.utc(2026, 7, 25, 12)   # past activated_at + 14d, but still before starts_on
    cat = @account.categories.create!(name: "Compras")
    g = active_goal(baseline: { "categories" => [ { "category_id" => cat.id, "median_cents" => 20_000 } ] })
    g.update!(starts_on: Date.new(2026, 8, 1))
    spend!(70_000, category: cat, on: Date.new(2026, 7, 22))   # would trip big_purchase outside grace
    result = Goals::Checker.call(g)
    assert_equal "on_track", result.status
    assert_empty result.findings
  end

  test "irregular-income guard: a low-income month suppresses the pace finding" do
    travel_to Time.utc(2026, 7, 31, 12)
    g = active_goal(baseline: { "median_income_cents" => 500_000 })
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 200_000,
                                  bank_account: @checking, occurred_on: Date.new(2026, 7, 3),
                                  billing_month: Date.new(2026, 7, 1))   # < 70% of baseline
    result = Goals::Checker.call(g)
    assert_empty result.findings
    assert_equal "on_track", result.status
  end

  test "a large commitment-less purchase trips a big_purchase finding" do
    travel_to Time.utc(2026, 7, 31, 12)
    cat = @account.categories.create!(name: "Compras")
    g = active_goal(baseline: { "categories" => [ { "category_id" => cat.id, "median_cents" => 20_000 } ] })
    save!(300_000)                          # on pace, so only the purchase can flag
    spend!(70_000, category: cat, on: Date.new(2026, 7, 28))   # ≥ max(3×20_000, 20%×300_000) = 60_000
    result = Goals::Checker.call(g)
    assert_equal "big_purchase", result.findings.first["finding"]
    assert_equal "at_risk", result.status
  end

  test "an everyday-sized purchase does not flag (calibration)" do
    travel_to Time.utc(2026, 7, 31, 12)
    cat = @account.categories.create!(name: "Mercado")
    g = active_goal(baseline: { "categories" => [ { "category_id" => cat.id, "median_cents" => 20_000 } ] })
    save!(300_000)
    spend!(20_000, category: cat, on: Date.new(2026, 7, 28))   # below the threshold
    assert_empty Goals::Checker.call(g).findings
  end
end
