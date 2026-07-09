require "test_helper"

# Reorganizar (.plans/goals round 4): offer quoting + the re-activation rewrite. The money
# traps: actual saved is INVARIANT across the rewrite (no double count at the month boundary),
# sobra gets the mid-month relief (unpaid occurrence archived), the earmark keeps the split
# page honest, budget cuts revert immediately, and history stays on the archived commitment.
class Goals::ReplanTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    travel_to Time.utc(2026, 7, 9, 12)
    history!   # Apr–Jun: 800k in / 200k out → live capacity 600k/month
  end

  teardown { travel_back }

  def history!
    [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ].each do |m|
      @account.transactions.create!(direction: "income", status: "posted", amount_cents: 800_000,
                                    bank_account: @checking, occurred_on: m + 4,
                                    billing_month: m, billing_month_manual: true)
      @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 200_000,
                                    bank_account: @checking, occurred_on: m + 10,
                                    billing_month: m, billing_month_manual: true)
    end
  end

  def active_goal(monthly: 300_000, initial: 0, plan: {})
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                           target_date: Date.new(2027, 12, 1), status: "active",
                           monthly_target_cents: monthly, starts_on: Date.new(2026, 6, 1),
                           activated_at: Time.utc(2026, 5, 20), bank_account: @caixinha,
                           initial_saved_cents: initial,
                           initial_saved_bank_account: (initial.positive? ? @caixinha : nil),
                           baseline: { "median_income_cents" => 800_000, "categories" => [] },
                           plan: { "projected_done_on" => "2028-02-01" }.merge(plan))
  end

  def commitment!(goal)
    @account.commitments.create!(kind: "savings", goal:, bank_account: @checking,
                                 amount_cents: goal.monthly_target_cents, name: goal.name,
                                 starts_on: goal.starts_on, ends_on: Date.new(2027, 12, 1),
                                 schedule_day: 7, schedule_kind: "fixed_day")
  end

  def save!(cents, month:)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  # ---- the offer -----------------------------------------------------------------------------

  test "offer: extend keeps the exact parcel and derives the finish; hold_date raises the parcel" do
    goal = active_goal
    save!(300_000, month: Date.new(2026, 6, 1))
    save!(150_000, month: Date.new(2026, 7, 1))          # July short by half
    offer = Goals::ReplanOffer.for(goal)
    assert_equal 450_000, offer.saved_cents
    assert_equal Date.new(2028, 2, 1), offer.promised_done_on   # the frozen plan's promise

    extend_option = offer.option("extend")
    assert_equal 300_000, extend_option.plan.monthly_target_cents
    # remaining 5.55M at 300k → 19 months from Aug 2026 → Mar 2028
    assert_equal Date.new(2028, 3, 1), extend_option.target_date

    hold = offer.option("hold_date")
    assert_equal Date.new(2027, 12, 1), hold.target_date
    # remaining 5.55M over months_between(Aug 2026, Dec 2027) = 16 → 346_875
    assert_equal 346_875, hold.plan.monthly_target_cents
  end

  test "offer: nil for savings_rate, drafts, achieved-level savings, and a hopeless capacity" do
    rate = @account.goals.create!(name: "Guardar", kind: "savings_rate", target_cents: 100_000,
                                  status: "active", monthly_target_cents: 100_000,
                                  starts_on: Date.new(2026, 6, 1), activated_at: Time.utc(2026, 5, 20),
                                  bank_account: @caixinha, baseline: {}, plan: {})
    assert_nil Goals::ReplanOffer.for(rate)

    goal = active_goal
    save!(6_000_000, month: Date.new(2026, 6, 1))        # already at target
    assert_nil Goals::ReplanOffer.for(goal)
  end

  test "offer: nil while the goal is on plan — nothing slipped, nothing to reorganize" do
    # A consistent on-plan goal: 6M at 300k from Jun = promise Feb 2028, asked date matching.
    goal = active_goal(plan: { "projected_done_on" => "2028-02-01" })
    goal.update!(target_date: Date.new(2028, 2, 1))
    save!(300_000, month: Date.new(2026, 6, 1))
    save!(300_000, month: Date.new(2026, 7, 1))          # extend derives ≤ the promise
    assert_nil Goals::ReplanOffer.for(goal)
  end

  test "offer: hold_date is hidden when infeasible or no earlier than extend" do
    goal = active_goal(monthly: 550_000, plan: { "projected_done_on" => "2027-06-01" })
    goal.update!(target_date: Date.new(2026, 9, 1))      # 1 month left → required ≈ 6M → infeasible
    offer = Goals::ReplanOffer.for(goal)
    assert_equal %w[extend], offer.options.map(&:mode)
  end

  # ---- the rewrite ---------------------------------------------------------------------------

  test "extend: actual saved is invariant, schedule re-anchors, commitment swaps with source carried" do
    goal = active_goal
    old_commitment = commitment!(goal)
    save!(300_000, month: Date.new(2026, 6, 1))
    save!(150_000, month: Date.new(2026, 7, 1))
    before = Goals::Progress.new(goal).actual_cents

    assert Goals::Replan.call(goal, mode: "extend").ok?
    goal.reload

    assert_equal before, Goals::Progress.new(goal).actual_cents   # the money trap
    assert_equal 300_000, goal.initial_saved_cents      # everything through June rebased in
    assert_equal @caixinha.id, goal.initial_saved_bank_account_id
    assert_equal Date.new(2026, 8, 1), goal.starts_on
    assert_equal Date.new(2028, 3, 1), goal.target_date
    assert_equal 300_000, goal.monthly_target_cents
    assert_equal "2026-07-09", goal.plan["replanned_on"]
    assert_equal "2027-12-01", goal.plan["previous_target_date"]

    assert old_commitment.reload.archived?
    fresh = goal.savings_commitment
    assert_equal @checking.id, fresh.bank_account_id     # source carried over
    assert_equal 7, fresh.schedule_day                   # payday carried over
    assert_equal Date.new(2026, 8, 1), fresh.starts_on
    # live remaining 5.55M at 300k → 19 parcels, last at Aug 2026 + 18 = Feb 2028
    assert_equal 19, fresh.parcels_count
    assert_equal Date.new(2028, 2, 1), fresh.ends_on
    assert_equal 0, fresh.paid_parcels_count             # parcels restart; history stays on the old row
    assert_equal 0, fresh.payments.count                 # no payment row was moved onto the new row
  end

  test "replanning mid-month relieves the sobra by exactly the unpaid parcel" do
    goal = active_goal
    commitment!(goal)                                    # July occurrence unpaid
    before = MonthSummary.new(@account, Date.new(2026, 7, 1)).remaining_cents
    assert Goals::Replan.call(goal, mode: "extend").ok?
    after = MonthSummary.new(@account, Date.new(2026, 7, 1)).remaining_cents
    assert_equal before + 300_000, after                 # projected_guardado dropped, nothing else moved
  end

  test "hold_date: the date stays and the parcel rises, on the goal and the fresh commitment" do
    goal = active_goal
    commitment!(goal)
    save!(300_000, month: Date.new(2026, 6, 1))
    save!(150_000, month: Date.new(2026, 7, 1))
    assert Goals::Replan.call(goal, mode: "hold_date").ok?
    goal.reload
    assert_equal Date.new(2027, 12, 1), goal.target_date
    assert_equal 346_875, goal.monthly_target_cents
    assert_equal 346_875, goal.savings_commitment.amount_cents
  end

  test "applied budget cuts revert immediately and the write-through re-arms for the new plan" do
    lazer = @account.categories.create!(name: "Lazer", monthly_budget_cents: 40_000)
    goal = active_goal(plan: { "cuts" => [ { "category_id" => lazer.id, "name" => "Lazer",
                                             "baseline_cents" => 55_000, "cap_cents" => 40_000 } ] })
    goal.update!(budgets_applied_at: Time.current, previous_budgets: { lazer.id.to_s => 55_000 })
    assert Goals::Replan.call(goal, mode: "extend").ok?
    assert_equal 55_000, lazer.reload.monthly_budget_cents   # standing budget restored now
    goal.reload
    assert_nil goal.budgets_applied_at                   # the daily job re-applies at the new starts_on
    assert_empty goal.previous_budgets
  end

  test "refuses a bad mode and a goal that is not active" do
    goal = active_goal
    assert_equal :invalid_mode, Goals::Replan.call(goal, mode: "yolo").error
    Goals::Abandon.call(goal)
    assert_equal :unavailable, Goals::Replan.call(goal.reload, mode: "extend").error
  end
end
