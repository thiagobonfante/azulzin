require "test_helper"

# Progress: guardado-vs-expected pace, pay-schedule-aware expected, irregular-income guard
# (.plans/goals 01 §6). Pace is never projected-sobra — a saver who contributes early is on track.
class Goals::ProgressTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
  end

  teardown { travel_back }

  def goal(**attrs)
    @account.goals.create!({ name: "Carro", kind: "purchase", target_cents: 6_000_000,
                             target_date: Date.new(2027, 12, 1), status: "active",
                             monthly_target_cents: 300_000, starts_on: Date.new(2026, 7, 1),
                             bank_account: @caixinha,
                             baseline: { "median_income_cents" => 500_000 } }.merge(attrs))
  end

  def save_to_caixinha!(cents:, month:)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  test "actual = initial head start + guardado since starts_on" do
    travel_to Time.utc(2026, 8, 20, 12)
    g = goal(initial_saved_cents: 50_000, initial_saved_bank_account: @caixinha)
    save_to_caixinha!(cents: 300_000, month: Date.new(2026, 7, 1))
    save_to_caixinha!(cents: 200_000, month: Date.new(2026, 8, 1))
    assert_equal 50_000 + 500_000, Goals::Progress.new(g).actual_cents
  end

  test "transfers before starts_on don't count toward the goal" do
    travel_to Time.utc(2026, 7, 20, 12)
    g = goal
    save_to_caixinha!(cents: 999_000, month: Date.new(2026, 6, 1))   # before the goal existed
    assert_equal 0, Goals::Progress.new(g).actual_cents
  end

  test "a linked caixinha ignores transfers into other savings accounts" do
    travel_to Time.utc(2026, 7, 20, 12)
    other = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    g = goal
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 400_000,
                                  bank_account: @checking, transfer_to_bank_account: other,
                                  occurred_on: Date.new(2026, 7, 5), billing_month: Date.new(2026, 7, 1),
                                  billing_month_manual: true)
    assert_equal 0, Goals::Progress.new(g).actual_cents
  end

  test "expected is 0 before the household's payday and pro-rates after it" do
    @account.incomes.create!(name: "Salário", amount_cents: 500_000, bank_account: @checking,
                             schedule_day: 10, schedule_kind: "fixed_day")
    g = goal   # starts July, so in July full_months_elapsed = 0

    travel_to Time.utc(2026, 7, 8, 12)          # before payday (day 10)
    assert_equal 0, Goals::Progress.new(g).expected_cents

    travel_to Time.utc(2026, 7, 20, 12)         # after payday: pro-rata 300_000 × (20−10)/(31−10)
    expected = Goals.prorate(300_000, 20 - 10, 31 - 10)
    assert_equal expected, Goals::Progress.new(g).expected_cents
  end

  test "full months elapsed accrue the whole monthly target" do
    travel_to Time.utc(2026, 9, 5, 12)   # Jul + Aug elapsed fully; Sep just started
    @account.incomes.create!(name: "Salário", amount_cents: 500_000, bank_account: @checking,
                             schedule_day: 10, schedule_kind: "fixed_day")
    g = goal
    # 2 full months × 300_000 + (Sep 5 is before payday → 0)
    assert_equal 600_000, Goals::Progress.new(g).expected_cents
  end

  test "a saver contributing on schedule is on pace (guardado ≥ expected, never punished for it)" do
    travel_to Time.utc(2026, 7, 20, 12)
    @account.incomes.create!(name: "Salário", amount_cents: 500_000, bank_account: @checking,
                             schedule_day: 5, schedule_kind: "fixed_day")
    g = goal
    save_to_caixinha!(cents: 300_000, month: Date.new(2026, 7, 1))   # already saved the whole month
    p = Goals::Progress.new(g)
    assert_operator p.actual_cents, :>=, p.expected_cents
  end

  test "irregular-income guard: a low-income month suppresses pace flagging" do
    travel_to Time.utc(2026, 7, 20, 12)
    g = goal   # baseline median income 500_000
    # only 200_000 income this month (< 70% of 500_000) → shortfall isn't behavior
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 200_000,
                                  bank_account: @checking, occurred_on: Date.new(2026, 7, 3),
                                  billing_month: Date.new(2026, 7, 1), billing_month_manual: true)
    refute Goals::Progress.new(g).pace_flag_allowed?
  end

  test "a normal-income month allows pace flagging" do
    travel_to Time.utc(2026, 7, 20, 12)
    g = goal
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 500_000,
                                  bank_account: @checking, occurred_on: Date.new(2026, 7, 3),
                                  billing_month: Date.new(2026, 7, 1), billing_month_manual: true)
    assert Goals::Progress.new(g).pace_flag_allowed?
  end

  # ── Round 3 decision 3: next-month start — the pre-start gap month ──────────────────────

  test "expected is 0 for the WHOLE activation gap month, even past the payday" do
    @account.incomes.create!(name: "Salário", amount_cents: 500_000, bank_account: @checking,
                             schedule_day: 10, schedule_kind: "fixed_day")
    g = goal(starts_on: Date.new(2026, 8, 1), activated_at: Time.utc(2026, 7, 15, 12))

    travel_to Time.utc(2026, 7, 20, 12)          # gap month, after the payday — the old MTD bug
    assert_equal 0, Goals::Progress.new(g).expected_cents

    travel_to Time.utc(2026, 8, 15, 12)          # schedule in force: pro-rata after the payday
    assert_operator Goals::Progress.new(g).expected_cents, :>, 0
  end

  test "an eager transfer in the gap month counts toward actual (guardado continua guardado)" do
    travel_to Time.utc(2026, 7, 20, 12)
    g = goal(starts_on: Date.new(2026, 8, 1), activated_at: Time.utc(2026, 7, 15, 12))
    save_to_caixinha!(cents: 120_000, month: Date.new(2026, 7, 1))   # before starts_on, after activation-month begin
    p = Goals::Progress.new(g)
    assert_equal 120_000, p.actual_cents
    assert_includes p.contributions.to_a.map(&:amount_cents), 120_000
  end

  test "purchase auto-achieves when the saved amount reaches the target" do
    travel_to Time.utc(2026, 7, 20, 12)
    g = goal(target_cents: 500_000)
    save_to_caixinha!(cents: 500_000, month: Date.new(2026, 7, 1))
    assert Goals::Progress.new(g).achieved?
  end

  # ── Round 3 decision 6: derived completion forecast ─────────────────────────────────────

  test "projected_done_on ceils remaining ÷ monthly from the current month" do
    travel_to Time.utc(2026, 8, 20, 12)
    g = goal   # target 6_000_000, monthly 300_000
    save_to_caixinha!(cents: 300_000, month: Date.new(2026, 8, 1))   # remaining 5_700_000 → 19 exactly
    assert_equal Date.new(2028, 3, 1), Goals::Progress.new(g).projected_done_on
  end

  test "projected_done_on: one cent past the exact division costs a whole month" do
    travel_to Time.utc(2026, 8, 20, 12)
    g = goal
    save_to_caixinha!(cents: 299_999, month: Date.new(2026, 8, 1))   # remaining 5_700_001 → ceil 20
    assert_equal Date.new(2028, 4, 1), Goals::Progress.new(g).projected_done_on
  end

  test "projected_done_on is the current month once the target is met; nil for savings_rate" do
    travel_to Time.utc(2026, 8, 20, 12)
    g = goal(target_cents: 100_000)
    save_to_caixinha!(cents: 100_000, month: Date.new(2026, 8, 1))
    assert_equal Date.new(2026, 8, 1), Goals::Progress.new(g).projected_done_on

    sr = @account.goals.create!(name: "Guardar", kind: "savings_rate", target_cents: 100_000,
                                status: "active", monthly_target_cents: 100_000,
                                starts_on: Date.new(2026, 7, 1), bank_account: @caixinha)
    assert_nil Goals::Progress.new(sr).projected_done_on
  end
end
