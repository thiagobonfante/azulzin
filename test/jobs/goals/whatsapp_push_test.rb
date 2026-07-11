require "test_helper"

# Phase 3 (.plans/goals 06 §2, 07 §3): the goals push, live. Consent/channel/claim are the spine's
# (tested there); goals adds the opt-in gate, the weekly-one-per-user guard, and the always-under-
# consent celebration.
class Goals::WhatsappPushTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user     = users(:confirmed)
    @account  = @user.account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    @user.update!(phone: "5511912345678", phone_verified_at: Time.current,
                  whatsapp_id: "5511912345678", whatsapp_jid: "5511912345678@c.us")
    @user.notification_prefs.update!(whatsapp_consent: true, goal_alerts: true, wa_intro_sent_at: 1.week.ago)
    WhatsappConnection.instance.update!(status: "connected")
    travel_to Time.utc(2026, 7, 31, 15)   # 12:00 SP — outside quiet hours
  end

  teardown { travel_back }

  def active_goal(name: "Carro", target: 6_000_000)
    @account.goals.create!(name:, kind: "purchase", target_cents: target, target_date: Date.new(2027, 12, 1),
                           status: "active", monthly_target_cents: 300_000, starts_on: Date.new(2026, 7, 1),
                           activated_at: Time.utc(2026, 7, 1), bank_account: @caixinha,
                           baseline: { "median_income_cents" => 0, "categories" => [] })
  end

  def save!(cents)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  occurred_on: Date.new(2026, 7, 1), billing_month: Date.new(2026, 7, 1),
                                  billing_month_manual: true)
  end

  def sweep
    bodies = []
    WhatsappService.stub(:send_message, ->(_to, body) { bodies << body; { id: "out" } }) do
      Goals::NotifyMemberJob.perform_now(@account.id, @user.id, Date.new(2026, 7, 31))
    end
    bodies
  end

  test "an opted-in member receives the goal_alert on WhatsApp" do
    active_goal   # unfunded → off_track
    bodies = sweep
    assert_equal 1, bodies.size
    assert_match "Carro", bodies.first
    assert Notification.where(kind: "goal_alert").last.whatsapp_sent_at.present?
  end

  test "goal_alerts off → dashboard row only, no push" do
    @user.notification_prefs.update!(goal_alerts: false)
    active_goal
    assert_empty sweep
    assert_nil Notification.where(kind: "goal_alert").last.whatsapp_sent_at
  end

  test "at most one goals message per user per week (weekly guard)" do
    active_goal(name: "Carro")
    active_goal(name: "Viagem")   # two off_track goals
    bodies = sweep
    assert_equal 1, bodies.size                                                        # only the first pushes
    assert_equal 2, Notification.where(kind: "goal_alert").count                       # both recorded (dashboard)
    assert_equal 1, Notification.where(kind: "goal_alert").where.not(whatsapp_sent_at: nil).count
  end

  test "goal_achieved is sent under consent even when goal_alerts is off (opt-out celebration)" do
    @user.notification_prefs.update!(goal_alerts: false)
    goal = active_goal(target: 300_000)
    save!(300_000)   # reaches target
    bodies = sweep
    assert(bodies.any? { |b| b.include?("Carro") })
    assert goal.reload.achieved?
    assert Notification.where(kind: "goal_achieved").last.whatsapp_sent_at.present?
  end

  # "Você guardou X" is a ledger figure: FLOOR, never overstate (matching the goal page party) —
  # unlike goal_alert's gap, which CEILs. Exploratory WEB-GOAL-06 caught the R$ 1 drift.
  test "goal_achieved floors the amount to whole reais" do
    goal = active_goal(target: 550_457)
    save!(550_457)
    bodies = sweep
    achieved = bodies.find { |b| b.include?("concluída") }
    assert achieved, "celebration must push"
    assert_includes achieved, "R$ 5.504"
    assert goal.reload.achieved?
  end

  test "sidecar disconnected → dashboard row, no send, claim not burned" do
    WhatsappConnection.instance.update!(status: "disconnected")
    active_goal
    assert_empty sweep
    assert_nil Notification.where(kind: "goal_alert").last.whatsapp_sent_at
  end
end
