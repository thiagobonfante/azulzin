require "test_helpers/e2e/pipeline_case"

# NT-GL: the goal guardian through the REAL weekly check — pace bands, the anti-nag
# delta-gate/cooldown, the weekly WA guard, and the always-celebrate promise
# (.plans/e2e/04 §3). goal_alerts defaults OFF; these scenarios opt in.
class E2E::NotificationGoalsTest < E2E::PipelineCase
  MONDAY      = Time.utc(2026, 5, 18, 15, 0)
  NEXT_MONDAY = Time.utc(2026, 5, 25, 15, 0)

  # NT-GL-01 — at-risk pace, golden with the exact gap
  test "pace at ~93% fires an at_risk goal_alert with the exact gap" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.3 ]))

    dispatch_goals!

    n = Notification.where(user: s.owner, kind: "goal_alert").sole
    assert_equal "pace", n.payload["finding"]
    # Expected at Monday day 18 = 2 full months + the day-5→18 pro-rata (half the month's
    # 26 post-payday days) = 2,5 × monthly; paid [1, 1, 0.3] saved 2,3 × monthly.
    gap_cents = (s.goal.monthly_target_cents * 0.2).round
    gap = WhatsappReply.currency(n.payload["gap_cents"], locale: :"pt-BR", whole: true)
    assert_equal gap_cents, n.payload["gap_cents"], "the gap is the month's unpaid slice, exact"
    assert_wa_reply s.jid, equals:
      "👀 Sua meta *Carro*: faltam #{gap} para o valor deste mês e o mês está acabando. " \
      "Uma transferência para a caixinha resolve. 💙"
  end

  # NT-GL-02
  test "pace at 50% is off_track" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 0.5, 0 ]))

    dispatch_goals!

    check = GoalCheck.where(goal: s.goal).order(:id).last
    assert_equal "off_track", check.status
    assert_wa_reply s.jid, includes: [ "Carro" ]
  end

  # NT-GL-11 — the post-activation grace
  test "on-track goals and freshly-activated goals stay silent" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 1 ]))

    dispatch_goals!

    assert_no_wa_reply s.jid
    assert_not Notification.exists?(user: s.owner, kind: "goal_alert")
  end

  # NT-GL-04/06 — the anti-nag promise: same cause next week is silent; the next month's
  # fresh cause re-arms after the cooldown
  test "delta-gate: silent on the same cause, re-armed by the next month's cause" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.3 ]))

    dispatch_goals!
    assert_equal 1, fake_sidecar.messages_to(s.jid).size

    travel_to NEXT_MONDAY
    dispatch_goals!
    assert_equal 1, fake_sidecar.messages_to(s.jid).size,
                 "same finding, same cause, same severity → not a peep"

    travel_to Time.utc(2026, 6, 8, 15, 0)   # 3 weeks later: cooldown passed, new month = new cause
    s.receive_income(Date.current.beginning_of_month)   # June salary lands (income guard stays open)
    dispatch_goals!
    assert_equal 2, fake_sidecar.messages_to(s.jid).size,
                 "the gate re-arms once the cause is genuinely new (round-4 fix)"
  end

  # NT-GL-09 — ≤1 goals WhatsApp message per user per week
  test "weekly WA guard: two slipping goals, one push, both dashboard rows" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.3 ]))
    second_caixinha = s.account.bank_accounts.create!(
      institution: Institution.find_by!(code: "260"), nickname: "Caixinha Viagem",
      kind: "savings", created_by: s.owner)
    s.add_active_goal!(name: "Viagem", paid: [ 1, 0.5, 0 ], target_cents: 1_000_000,
                       into: second_caixinha)

    dispatch_goals!

    assert_equal 1, fake_sidecar.messages_to(s.jid).size, "one goals push per user per week"
    assert_equal 2, Notification.where(user: s.owner, kind: "goal_alert").count,
                 "both goals still get their dashboard rows"
  end

  # NT-GL-10 — always celebrate: every member, exempt from the weekly guard
  test "goal_achieved reaches every member even after a goal alert the same week" do
    travel_to MONDAY
    s = E2E::Scenario.build(:couple)
    s.add_caixinha!
    goal = s.add_active_goal!(name: "Reserva", paid: [ 1, 1, 0.3 ])
    s.members.each do |m|
      m.notification_prefs.update!(whatsapp_consent: true, goal_alerts: true,
                                   goal_achieved: true, wa_intro_sent_at: Time.current)
    end
    wa_connect!

    dispatch_goals!   # burns the weekly goals slot with the pace alert
    s.stash(goal.target_cents, on: Date.current)   # cross the finish line

    travel 1.day      # a fresh day for the daily cap; the weekly guard is the thing under test
    dispatch_goals!

    s.members.each do |m|
      achieved = fake_sidecar.messages_to(s.jid(m)).map(&:body)
                             .select { |b| b.include?("concluída") }
      assert_equal 1, achieved.size, "#{m.display_name} must get the celebration"
      assert_includes achieved.sole, "*Reserva*"
    end
    assert goal.reload.achieved?
  end

  # NT-GL-12 — the low-income month suppresses pace, never celebrates less
  test "a low-income month suppresses the pace nag" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.3 ]))
    # Shrink this month's received income under 70% of the baseline median.
    s.account.transactions.where(direction: "income", billing_month: Date.current.beginning_of_month)
     .update_all(amount_cents: 300_000)

    dispatch_goals!

    assert_no_wa_reply s.jid
    assert_not Notification.exists?(user: s.owner, kind: "goal_alert"),
               "pace must not nag someone whose income dipped"
  end

  private

  def push_ready(s)
    s.wa_verified!(consent: true)
    s.owner.notification_prefs.update!(goal_alerts: true, goal_achieved: true,
                                       wa_intro_sent_at: Time.current)
    wa_connect!
    s
  end

  def dispatch_goals!
    Goals::WeeklyCheckDispatchJob.perform_now
    drain_jobs!
  end
end
