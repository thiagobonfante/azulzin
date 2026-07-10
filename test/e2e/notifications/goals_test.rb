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

  # NT-GL-05 — the cooldown gates a WORSENING non-urgent lead. An at_risk pace alert last Monday,
  # then the pace slips to off_track this Monday (expected rises through the month while actual
  # holds: ratio ~88% at day 18 → ~79% at day 25). The worsening beats the DELTA-GATE, but the
  # 14-day cooldown still suppresses it — the shipped contract is that ONLY urgent leads
  # (missed_month/red_month/next_month_red) bypass the cooldown, pinned in
  # notify_member_job_test.rb ("a non-urgent budget_raised new cause stays silent inside the
  # cooldown"). No new push, no new goal_alert row until the cooldown lifts (NT-GL-06 day-15).
  #
  # NOTE (vetoable): spec 04 §NT-GL-05 predicts the worsening FIRES inside the cooldown; the
  # shipped, unit-tested anti-nag design is the opposite. Pinning real behavior, discrepancy
  # recorded in 07-coverage-audit.md.
  test "a worsening pace inside the cooldown stays silent (only urgent leads bypass it)" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.2 ]))

    dispatch_goals!
    assert_equal "at_risk", GoalCheck.where(goal: s.goal).order(:id).last.status
    assert_equal 1, fake_sidecar.messages_to(s.jid).size, "week 1: the at_risk alert"
    assert_equal 1, Notification.where(user: s.owner, kind: "goal_alert").count

    travel_to NEXT_MONDAY   # 7 days later — inside the cooldown; expected has risen past actual
    dispatch_goals!

    assert_equal "off_track", GoalCheck.where(goal: s.goal).order(:id).last.status,
                 "the severity genuinely worsened this week"
    assert_equal 1, fake_sidecar.messages_to(s.jid).size,
                 "the cooldown gates the worsening non-urgent lead — no second push"
    assert_equal 1, Notification.where(user: s.owner, kind: "goal_alert").count,
                 "and no new goal_alert row (the cooldown returns before record!)"
  end

  # NT-GL-07 — an urgent missed_month finding bypasses the 14-day cooldown (never the delta-gate:
  # it's a genuinely new cause). Week 1 (Mon May 25) a pace alert arms the cooldown; week 2
  # (Mon Jun 1, 7 days later, still inside the cooldown) May has closed under its parcel → the
  # missed_month empathy push breaks through. Golden pinned. Spec 04 §NT-GL-07.
  test "missed_month is urgent and bypasses the cooldown; empathy golden" do
    travel_to Time.utc(2026, 5, 25, 15, 0)   # Monday, last week of May
    s = missed_month_scenario

    dispatch_goals!
    assert_equal 1, fake_sidecar.messages_to(s.jid).size, "week 1: a pace alert arms the cooldown"

    travel_to Time.utc(2026, 6, 1, 15, 0)    # Monday, 7 days later — inside the 14-day cooldown
    dispatch_goals!

    msgs = fake_sidecar.messages_to(s.jid)
    assert_equal 2, msgs.size, "the urgent missed_month breaks through the cooldown"
    assert_equal msgs.last.body,
      "👀 A meta *Carro* ficou R$ 2.500 abaixo do combinado no mês passado.\n" \
      "No ritmo atual, a conclusão passa de novembro de 2027 para dezembro de 2027.\n" \
      "Responda *reorganizar* para ajustar o plano."
    n = Notification.where(user: s.owner, kind: "goal_alert").newest_first.first
    assert_equal "missed_month", n.payload["finding"]
    assert n.whatsapp_sent_at.present?, "it delivered (bypassed the cooldown, respected the delta-gate)"
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

  # A slipped purchase goal (target R$ 60.000, promised nov/2027) with a real savings commitment:
  # March + April parcels paid in full, May paid partial → at Jun 1 May has closed under the
  # parcel and the honest finish slips past the promise, firing missed_month. goal_active can't
  # slip (its parcel over-covers its backdated window), so this is built inline like WA-GOAL-05.
  def missed_month_scenario
    s = push_ready(E2E::Scenario.build(:solo_basic) { |sc| sc.add_caixinha!; sc.ensure_income_history! })
    start = Date.new(2026, 3, 1)
    goal = s.account.goals.create!(
      name: "Carro", kind: "purchase", target_cents: 6_000_000, target_date: Date.new(2027, 12, 1),
      status: "active", monthly_target_cents: 300_000, starts_on: start, activated_at: start.in_time_zone,
      bank_account: s.caixinha, created_by: s.owner,
      baseline: { "median_income_cents" => 0, "categories" => [] },
      plan: { "projected_done_on" => "2027-11-01" })
    commitment = s.account.commitments.create!(kind: "savings", goal: goal, bank_account: s.itau,
      amount_cents: 300_000, name: "Carro", starts_on: start, schedule_day: 5,
      schedule_kind: "fixed_day", created_by: s.owner)
    [ Date.new(2026, 3, 1), Date.new(2026, 4, 1) ].each { |m| pay_savings(s, commitment, m, 300_000) }
    pay_savings(s, commitment, Date.new(2026, 5, 1), 50_000)   # May under the parcel → the miss
    s.instance_variable_set(:@goal, goal)
    s
  end

  def pay_savings(s, commitment, month, amount)
    Commitments::MarkPaid.call(commitment, month, amount: amount, created_by: s.owner)
               .update_columns(occurred_on: month + 4, created_at: (month + 4).in_time_zone)
  end

  def dispatch_goals!
    Goals::WeeklyCheckDispatchJob.perform_now
    drain_jobs!
  end
end
