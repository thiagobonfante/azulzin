require "test_helper"

# Weekly guardian, record-only phase (.plans/goals 06 §2): idempotent goal_checks, dashboard
# notification rows on alert-worthy moments only, zero WhatsApp.
class Goals::NotifyMemberJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user     = users(:confirmed)
    @account  = @user.account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
  end

  teardown { travel_back }

  def active_goal(monthly: 300_000, target: 6_000_000, activated_at: Time.utc(2026, 7, 1))
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: target,
                           target_date: Date.new(2027, 12, 1), status: "active", monthly_target_cents: monthly,
                           starts_on: Date.new(2026, 7, 1), activated_at:, bank_account: @caixinha,
                           baseline: { "median_income_cents" => 0, "categories" => [] })
  end

  def save!(cents, month: Date.new(2026, 7, 1))
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  def sweep(as_of) = Goals::NotifyMemberJob.perform_now(@account.id, @user.id, as_of)

  test "writes exactly one goal_checks row per goal per week, even run twice" do
    travel_to Time.utc(2026, 7, 31, 12)
    goal = active_goal
    assert_difference -> { GoalCheck.count }, 1 do
      sweep(Date.new(2026, 7, 31))
      sweep(Date.new(2026, 7, 31))
    end
    assert_equal Date.new(2026, 7, 27), goal.checks.first.period_start   # ISO Monday
  end

  test "an off_track goal records a goal_alert dashboard row and NO WhatsApp (record-only)" do
    travel_to Time.utc(2026, 7, 31, 12)
    active_goal   # nothing saved → off_track
    assert_difference -> { Notification.where(kind: "goal_alert").count }, 1 do
      sweep(Date.new(2026, 7, 31))
    end
    assert_nil Notification.where(kind: "goal_alert").last.whatsapp_sent_at
  end

  test "an on_track goal writes a check but records no notification" do
    travel_to Time.utc(2026, 7, 31, 12)
    active_goal
    save!(300_000)
    assert_no_difference -> { Notification.count } do
      sweep(Date.new(2026, 7, 31))
    end
    assert_equal "on_track", GoalCheck.last.status
  end

  test "delta-gate: the same finding two weeks running fires once, then stays silent" do
    goal = active_goal
    travel_to Time.utc(2026, 7, 31, 12)
    sweep(Date.new(2026, 7, 31))                        # week 1: off_track → 1 alert
    assert_equal 1, Notification.where(kind: "goal_alert").count
    travel_to Time.utc(2026, 8, 7, 12)
    assert_no_difference -> { Notification.where(kind: "goal_alert").count } do
      sweep(Date.new(2026, 8, 7))                       # same cause, still within cooldown → silent
    end
  end

  test "within the activation grace, an unfunded goal produces an on_track check and no alert" do
    travel_to Time.utc(2026, 7, 10, 12)
    active_goal(activated_at: Time.utc(2026, 7, 1))   # grace until Jul 15
    assert_no_difference -> { Notification.count } do
      sweep(Date.new(2026, 7, 10))
    end
    assert_equal "on_track", GoalCheck.last.status
  end

  test "a goal that reaches its target flips achieved and records goal_achieved once" do
    travel_to Time.utc(2026, 7, 31, 12)
    goal = active_goal(target: 300_000)
    save!(300_000)   # actual ≥ target
    assert_difference -> { Notification.where(kind: "goal_achieved").count }, 1 do
      sweep(Date.new(2026, 7, 31))
    end
    assert goal.reload.achieved?
    assert_nil goal.savings_commitment   # commitment archived on achieve
  end

  test "every member of a household gets goal_achieved even though the goal leaves 'active' on the first flip" do
    other = User.create!(email_address: "member2@example.com", password: "password123")
    @account.add_member!(other)
    travel_to Time.utc(2026, 7, 31, 12)
    active_goal(target: 300_000)
    save!(300_000)
    sweep(Date.new(2026, 7, 31))   # @user's job flips the goal and notifies all members
    assert Notification.where(kind: "goal_achieved", user: @user).exists?
    assert Notification.where(kind: "goal_achieved", user: other).exists?
  end
end
