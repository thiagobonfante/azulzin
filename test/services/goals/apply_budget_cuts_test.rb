require "test_helper"

# Activating a goal writes its cuts into the standing category budgets at starts_on and reverts
# them on abandon/achieve (round 3 decision 2): min-tighten only, snapshot previous values,
# manual edits win, other active goals' caps survive a sibling's revert.
class Goals::ApplyBudgetCutsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  JULY   = Date.new(2026, 7, 1)
  AUGUST = Date.new(2026, 8, 1)

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    @rest     = @account.categories.create!(name: "Restaurantes")
    travel_to Time.utc(2026, 7, 15, 12)
  end

  teardown { travel_back }

  def goal(cuts:, starts_on: JULY, **attrs)
    @account.goals.create!({ name: "Carro", kind: "purchase", target_cents: 6_000_000,
                             target_date: Date.new(2027, 12, 1), status: "active",
                             monthly_target_cents: 300_000, starts_on:, activated_at: Time.utc(2026, 6, 15),
                             bank_account: @caixinha, baseline: {},
                             plan: { "cuts" => cuts } }.merge(attrs))
  end

  def cut_for(category, cap) = { "category_id" => category.id, "name" => category.name, "baseline_cents" => 60_000, "cap_cents" => cap }

  test "tightens a looser standing budget to the cap and snapshots the previous value" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    assert Goals::ApplyBudgetCuts.call(g)
    assert_equal 40_000, @rest.reload.monthly_budget_cents
    assert_not_nil g.budgets_applied_at
    assert_equal({ @rest.id.to_s => 60_000 }, g.previous_budgets)
  end

  test "creates a budget on an unbudgeted category, snapshotting nil" do
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    assert Goals::ApplyBudgetCuts.call(g)
    assert_equal 40_000, @rest.reload.monthly_budget_cents
    assert_equal({ @rest.id.to_s => nil }, g.previous_budgets)
  end

  test "never loosens: an already-tighter budget stands and is not snapshotted" do
    @rest.update!(monthly_budget_cents: 30_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    assert Goals::ApplyBudgetCuts.call(g)                    # goal is still marked applied
    assert_equal 30_000, @rest.reload.monthly_budget_cents
    assert_empty g.previous_budgets
  end

  test "skips a full-trim R$0 cap (cannot violate the > 0 budget validation)" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 0) ])
    assert Goals::ApplyBudgetCuts.call(g)
    assert_equal 60_000, @rest.reload.monthly_budget_cents
    assert_empty g.previous_budgets
  end

  test "skips soft-deleted categories" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    @rest.soft_delete!(by: users(:confirmed))
    assert Goals::ApplyBudgetCuts.call(g)
    assert_equal 60_000, @rest.reload.monthly_budget_cents
  end

  test "no-ops before starts_on (the sweep is the single apply path) and when not active" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ], starts_on: AUGUST)
    refute Goals::ApplyBudgetCuts.call(g)
    assert_equal 60_000, @rest.reload.monthly_budget_cents
    assert_nil g.reload.budgets_applied_at

    d = goal(cuts: [ cut_for(@rest, 40_000) ], status: "draft", starts_on: nil, activated_at: nil, monthly_target_cents: nil)
    refute Goals::ApplyBudgetCuts.call(d)
  end

  test "idempotent: a second run is a no-op and never re-snapshots or re-tightens" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    assert Goals::ApplyBudgetCuts.call(g)
    @rest.update!(monthly_budget_cents: 55_000)              # member re-edits after apply
    refute Goals::ApplyBudgetCuts.call(g)
    assert_equal 55_000, @rest.reload.monthly_budget_cents
    assert_equal({ @rest.id.to_s => 60_000 }, g.reload.previous_budgets)
  end

  test "the daily job sweeps eligible goals" do
    @rest.update!(monthly_budget_cents: 60_000)
    goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCutsJob.perform_now
    assert_equal 40_000, @rest.reload.monthly_budget_cents
  end

  # ── Revert on abandon / achieve ─────────────────────────────────────────────────────────

  test "abandon restores the previous budget" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCuts.call(g)
    assert Goals::Abandon.call(g)
    assert_equal 60_000, @rest.reload.monthly_budget_cents
  end

  test "achieve restores the previous budget too (celebrate AND loosen)" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCuts.call(g)
    assert Goals::Achieve.call(g)
    assert g.achieved?
    assert_equal 60_000, @rest.reload.monthly_budget_cents
  end

  test "revert clears a budget the apply created (previous was nil)" do
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCuts.call(g)
    Goals::Abandon.call(g)
    assert_nil @rest.reload.monthly_budget_cents
  end

  test "a manual edit after apply wins — revert leaves it alone" do
    @rest.update!(monthly_budget_cents: 60_000)
    g = goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCuts.call(g)
    @rest.update!(monthly_budget_cents: 35_000)              # the member's own call since apply
    Goals::Abandon.call(g)
    assert_equal 35_000, @rest.reload.monthly_budget_cents
  end

  test "revert respects another active applied goal's tighter cap on the same category" do
    @rest.update!(monthly_budget_cents: 60_000)
    a = goal(cuts: [ cut_for(@rest, 40_000) ])
    Goals::ApplyBudgetCuts.call(a)                           # budget 60_000 → 40_000, prev 60_000
    b = goal(cuts: [ cut_for(@rest, 35_000) ], name: "Viagem")
    Goals::ApplyBudgetCuts.call(b)                           # budget 40_000 → 35_000, prev 40_000

    Goals::Abandon.call(b)                                   # b's revert: min(prev 40_000, a's cap 40_000)
    assert_equal 40_000, @rest.reload.monthly_budget_cents

    Goals::Abandon.call(a)                                   # a's revert: no remaining caps → prev 60_000
    assert_equal 60_000, @rest.reload.monthly_budget_cents
  end
end
