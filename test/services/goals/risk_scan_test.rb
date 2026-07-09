require "test_helper"

# The predictive arm (.plans/goals round 4): red projections, budget raises above a goal cap,
# and the missed-month post-mortem with its deterministic cause + empathy fork. Zero LLM.
class Goals::RiskScanTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    travel_to Time.utc(2026, 7, 9, 12)
  end

  teardown { travel_back }

  AS_OF = Date.new(2026, 7, 9)

  def active_goal(name: "Carro", monthly: 300_000, starts_on: Date.new(2026, 7, 1), baseline: {}, plan: {})
    @account.goals.create!(name:, kind: "purchase", target_cents: 6_000_000,
                           target_date: Date.new(2027, 12, 1), status: "active",
                           monthly_target_cents: monthly, starts_on:,
                           activated_at: Time.utc(2026, 6, 15), bank_account: @caixinha,
                           baseline: { "median_income_cents" => 0, "categories" => [] }.merge(baseline),
                           plan:)
  end

  def commitment!(goal, monthly: goal.monthly_target_cents, starts_on: goal.starts_on)
    @account.commitments.create!(kind: "savings", goal:, bank_account: @checking,
                                 amount_cents: monthly, name: goal.name, starts_on:,
                                 schedule_day: 5, schedule_kind: "fixed_day")
  end

  def save!(cents, month:)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  def spend!(cents, category:, on:)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                  category:, bank_account: @checking, occurred_on: on,
                                  billing_month: on.beginning_of_month, billing_month_manual: true)
  end

  def scan = Goals::RiskScan.call(@account, as_of: AS_OF)

  # ---- red_month ---------------------------------------------------------------------------

  test "red_month fires when the month projects negative with a goal parcel in it" do
    goal = active_goal
    commitment!(goal)                          # unpaid Jul occurrence, no income → remaining −300k
    finding = scan[goal.id].find { |f| f["finding"] == "red_month" }
    assert finding, "expected a red_month finding"
    assert_equal 300_000, finding["shortfall_cents"]
    assert_equal 300_000, finding["committed_cents"]
    assert finding["urgent"]
  end

  test "red_month stays silent when income covers the month" do
    goal = active_goal
    commitment!(goal)
    @account.incomes.create!(bank_account: @checking, name: "salário", amount_cents: 400_000,
                             schedule_kind: "fixed_day", schedule_day: 5)   # projects into Jul AND Aug
    assert_empty scan[goal.id]
  end

  test "red_month stays silent when no goal parcel sits in the red month" do
    goal = active_goal(starts_on: Date.new(2026, 8, 1))
    commitment!(goal)                                   # first occurrence in August
    spend!(50_000, category: nil, on: Date.new(2026, 7, 2))   # July is red, but not because of goals
    assert_nil scan[goal.id].find { |f| f["finding"] == "red_month" }
  end

  test "red_month attaches once, to the goal with the largest parcel" do
    small = active_goal(name: "Viagem", monthly: 300_000)
    big   = active_goal(name: "Carro",  monthly: 500_000)
    commitment!(small)
    commitment!(big)
    result = scan
    assert_nil result[small.id].find { |f| f["finding"] == "red_month" }
    assert_equal "Carro", result[big.id].find { |f| f["finding"] == "red_month" }["goal"]
  end

  # ---- next_month_red ----------------------------------------------------------------------

  test "next_month_red fires ahead: card spend already billing next month breaks the first parcel" do
    goal = active_goal(starts_on: Date.new(2026, 8, 1))   # gap month — parcel only in August
    commitment!(goal)
    card = @account.credit_cards.create!(institution: @inst)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 500_000,
                                  credit_card: card, occurred_on: Date.new(2026, 7, 5),
                                  billing_month: Date.new(2026, 8, 1), billing_month_manual: true)
    finding = scan[goal.id].find { |f| f["finding"] == "next_month_red" }
    assert finding, "expected a next_month_red finding"
    assert_equal 800_000, finding["shortfall_cents"]   # 500k fatura + 300k parcel, zero income
    assert_equal 500_000, finding["faturas_cents"]
    assert finding["urgent"]
  end

  test "a goal replanned in the last fortnight sits out the red projections (quiet switch)" do
    replanned = active_goal(name: "Carro")
    replanned.update!(plan: { "replanned_on" => "2026-07-05" })   # 4 days before AS_OF
    commitment!(replanned)
    other = active_goal(name: "Viagem", monthly: 200_000)
    commitment!(other)
    result = scan
    assert_empty result[replanned.id]
    assert_equal "Viagem", result[other.id].find { |f| f["finding"] == "red_month" }["goal"]
  end

  # ---- missed_month ------------------------------------------------------------------------

  test "missed_month fires when last month came in under the parcel, with the derived new date" do
    goal = active_goal(starts_on: Date.new(2026, 6, 1))
    save!(100_000, month: Date.new(2026, 6, 1))          # 100k of the 300k parcel
    finding = scan[goal.id].find { |f| f["finding"] == "missed_month" }
    assert finding, "expected a missed_month finding"
    assert_equal 200_000, finding["gap_cents"]
    assert_equal 100_000, finding["saved_cents"]
    assert_equal "2027-12-01", finding["old_month"]      # falls back to target_date (no plan snapshot)
    # remaining 5.9M at 300k/month → 20 months from July → 2028-03
    assert_equal "2028-03-01", finding["new_month"]
    assert_equal "plain", finding["variant"]             # no baseline categories → no cause named
    assert finding["urgent"]
  end

  test "missed_month names the worst overage; an essential category gets the gentle variant" do
    saude = @account.categories.create!(name: "Saúde")
    goal = active_goal(starts_on: Date.new(2026, 6, 1), baseline: {
      "categories" => [ { "category_id" => saude.id, "name" => "Saúde",
                          "median_cents" => 50_000, "flexibility" => "essential" } ]
    })
    save!(100_000, month: Date.new(2026, 6, 1))
    spend!(150_000, category: saude, on: Date.new(2026, 6, 20))
    finding = scan[goal.id].find { |f| f["finding"] == "missed_month" }
    assert_equal "essential", finding["variant"]
    assert_equal "Saúde", finding["category"]
    assert_equal 100_000, finding["over_cents"]
  end

  test "missed_month: a flexible-category cause carries no variant (direct copy)" do
    lazer = @account.categories.create!(name: "Lazer")
    goal = active_goal(starts_on: Date.new(2026, 6, 1), baseline: {
      "categories" => [ { "category_id" => lazer.id, "name" => "Lazer",
                          "median_cents" => 30_000, "flexibility" => "flexible" } ]
    })
    save!(100_000, month: Date.new(2026, 6, 1))
    spend!(90_000, category: lazer, on: Date.new(2026, 6, 20))
    finding = scan[goal.id].find { |f| f["finding"] == "missed_month" }
    assert_nil finding["variant"]
    assert_equal "Lazer", finding["category"]
  end

  test "missed_month: a low-income month wins as the cause, even over a category overage" do
    lazer = @account.categories.create!(name: "Lazer")
    goal = active_goal(starts_on: Date.new(2026, 6, 1), baseline: {
      "median_income_cents" => 500_000,                  # June posted income = 0 → < 70%
      "categories" => [ { "category_id" => lazer.id, "name" => "Lazer",
                          "median_cents" => 30_000, "flexibility" => "flexible" } ]
    })
    save!(100_000, month: Date.new(2026, 6, 1))
    spend!(90_000, category: lazer, on: Date.new(2026, 6, 20))
    finding = scan[goal.id].find { |f| f["finding"] == "missed_month" }
    assert_equal "income", finding["variant"]
    assert_nil finding["category"]
  end

  test "missed_month stays silent when the parcel was met, the schedule had not started, or nothing slipped" do
    met = active_goal(name: "Met", starts_on: Date.new(2026, 6, 1))
    save!(300_000, month: Date.new(2026, 6, 1))
    assert_empty scan[met.id]

    fresh = active_goal(name: "Fresh", starts_on: Date.new(2026, 7, 1))   # June owed nothing
    assert_nil scan[fresh.id].find { |f| f["finding"] == "missed_month" }

    # The chosen plan already promised a later date than the derived one → no slip, no alert.
    slack = active_goal(name: "Slack", starts_on: Date.new(2026, 6, 1),
                        plan: { "projected_done_on" => "2028-06-01" })
    assert_nil scan[slack.id].find { |f| f["finding"] == "missed_month" }
  end

  # ---- budget_raised -----------------------------------------------------------------------

  test "budget_raised fires when a standing budget is raised above an applied goal cap" do
    lazer = @account.categories.create!(name: "Lazer", monthly_budget_cents: 60_000)
    goal = active_goal(plan: { "cuts" => [ { "category_id" => lazer.id, "name" => "Lazer",
                                             "baseline_cents" => 55_000, "cap_cents" => 40_000 } ] })
    goal.update!(budgets_applied_at: Time.current)
    finding = scan[goal.id].find { |f| f["finding"] == "budget_raised" }
    assert finding, "expected a budget_raised finding"
    assert_equal lazer.id, finding["category_id"]
    assert_equal 20_000, finding["over_cents"]
    assert_not finding["urgent"]                         # stays under the cooldown
  end

  test "budget_raised is silent at/below the cap and before the write-through applied" do
    lazer = @account.categories.create!(name: "Lazer", monthly_budget_cents: 40_000)
    goal = active_goal(plan: { "cuts" => [ { "category_id" => lazer.id, "name" => "Lazer",
                                             "baseline_cents" => 55_000, "cap_cents" => 40_000 } ] })
    goal.update!(budgets_applied_at: Time.current)
    assert_nil scan[goal.id].find { |f| f["finding"] == "budget_raised" }

    lazer.update!(monthly_budget_cents: 60_000)
    goal.update!(budgets_applied_at: nil)                # not applied yet → budgets legitimately higher
    assert_nil scan[goal.id].find { |f| f["finding"] == "budget_raised" }
  end
end
