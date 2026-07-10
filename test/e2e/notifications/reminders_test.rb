require "test_helpers/e2e/pipeline_case"

# NT-R: reminder kinds through the REAL daily dispatch (.plans/e2e/04 §3). Golden bodies
# are literal — copy or interpolation drift must turn this file red.
class E2E::NotificationRemindersTest < E2E::PipelineCase
  # NT-R-01 — golden + pluralization edges (hoje / amanhã / em N dias)
  test "bill_due: vence amanhã, exact golden" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    fixed_bill(s, "Condomínio", 48_000, due: Date.current + 1)

    dispatch_reminders!

    assert_wa_reply s.jid, equals: "🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙"
  end

  test "bill_due: vence hoje and em N dias variants" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    s.owner.notification_prefs.update!(bill_reminder_lead_days: 5)
    fixed_bill(s, "Aluguel", 220_000, due: Date.current)
    fixed_bill(s, "Internet", 11_990, due: Date.current + 5)

    dispatch_reminders!

    bodies = fake_sidecar.messages_to(s.jid).map(&:body)
    assert_includes bodies, "🔔 Sua conta *Aluguel* (R$ 2.200,00) vence hoje. 💙"
    assert_includes bodies, "🔔 Sua conta *Internet* (R$ 119,90) vence em 5 dias. 💙"
  end

  # NT-R-02 — overdue inside the 3-day grace fires; outside stays silent
  test "bill_overdue: venceu há 2 dias fires, 5 days is outside the grace" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    fixed_bill(s, "Luz", 18_500, due: Date.current - 2)
    fixed_bill(s, "Água", 9_500, due: Date.current - 5)

    dispatch_reminders!

    assert_wa_reply s.jid, equals: "⚠️ Sua conta *Luz* (R$ 185,00) venceu há 2 dias. Já pagou?"
    assert_not Notification.exists?(user: s.owner, kind: "bill_overdue", payload: { name: "Água" }),
               "outside the grace no row is even recorded"
    assert_equal 1, fake_sidecar.messages_to(s.jid).size
  end

  # NT-R-03 — closing carries the running open-bill amount
  test "card_closing: fecha amanhã with the exact open-bill cents" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    s.nubank_card.update!(bill_due_day: (Date.current + 8).day, closing_offset_days: 7)
    s.expense(merchant: "Compra na Fatura", category: "Outros", instrument: s.nubank_card,
              cents: 25_000, on: Date.current - 3)

    dispatch_reminders!

    assert_wa_reply s.jid, equals: "📄 A fatura do *Nubank* fecha amanhã — R$ 250,00 até agora."
  end

  # NT-R-04 — due carries the CLOSED bill amount
  test "card_due: vence amanhã with the closed-bill cents" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    s.nubank_card.update!(bill_due_day: (Date.current + 1).day, closing_offset_days: 7)
    s.expense(merchant: "Compra Fechada", category: "Outros", instrument: s.nubank_card,
              cents: 25_000, on: Date.current - 10)

    dispatch_reminders!

    assert_wa_reply s.jid, equals: "📄 A fatura do *Nubank* (R$ 250,00) vence amanhã. 💙"
  end

  # NT-R-05 — the ±10% received-match, both sides of the boundary
  test "income_expected: fires unless a deposit within ±10% already landed" do
    { nil => 1, 109_200 => 0, 106_800 => 1 }.each do |deposit_cents, expected_pushes|
      s = push_ready(E2E::Scenario.build(:solo_basic))
      s.account.incomes.create!(name: "Freela", bank_account: s.itau, amount_cents: 120_000,
                                schedule_day: (Date.current + 1).day, created_by: s.owner)
      if deposit_cents
        s.account.transactions.create!(
          merchant: "Pix Freela", direction: "income", status: "posted", source: "manual",
          amount_cents: deposit_cents, occurred_on: Date.current - 1,
          confirmed_at: Time.current, bank_account: s.itau, created_by: s.owner)
      end

      dispatch_reminders!

      msgs = fake_sidecar.messages_to(s.jid).select { |m| m.body.include?("Freela") }
      assert_equal expected_pushes, msgs.size,
                   "deposit #{deposit_cents.inspect} → #{expected_pushes} push(es)"
      if expected_pushes == 1
        assert_equal "💰 Seu *Freela* de R$ 1.200,00 deve cair amanhã. 💙", msgs.sole.body
      end
      fake_sidecar.reset!
    end
  end

  # NT-R-06 — the lead window is [today, today + bill_reminder_lead_days], at both pref extremes.
  # lead 0 → only today's bill; lead 7 → up to a week out, but not day 8. Spec 04 §NT-R (NT-R-06).
  test "bill_reminder_lead_days shifts the bill_due window exactly at 0 and 7" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    s.owner.notification_prefs.update!(bill_reminder_lead_days: 0)
    fixed_bill(s, "Hoje",   40_000, due: Date.current)
    fixed_bill(s, "Amanhã", 50_000, due: Date.current + 1)

    dispatch_reminders!
    names = Notification.where(user: s.owner, kind: "bill_due").pluck(Arel.sql("payload->>'name'"))
    assert_equal %w[Hoje], names, "lead 0: only today's bill is in the window"
    fake_sidecar.reset!

    s2 = push_ready(E2E::Scenario.build(:solo_basic))
    s2.owner.notification_prefs.update!(bill_reminder_lead_days: 7)
    fixed_bill(s2, "Em7Dias", 60_000, due: Date.current + 7)
    fixed_bill(s2, "Em8Dias", 70_000, due: Date.current + 8)

    Reminders::DailyDispatchJob.perform_now
    drain_jobs!
    names2 = Notification.where(user: s2.owner, kind: "bill_due").pluck(Arel.sql("payload->>'name'"))
    assert_equal %w[Em7Dias], names2, "lead 7: day 7 fires, day 8 is outside the window"
  end

  # NT-R-07 — a payment before dispatch silences the reminder; re-dispatch dedups
  test "a bill paid via WhatsApp is not reminded, and a re-dispatch sends nothing new" do
    s = push_ready(E2E::Scenario.build(:reminders_due))

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "condomínio")) do
      wa_inject(s.jid, "paguei o condomínio")
      drain_jobs!
    end
    fake_sidecar.reset!

    dispatch_reminders!
    first_run = fake_sidecar.messages_to(s.jid).map(&:body)
    assert first_run.none? { |b| b.include?("Condomínio") }, "a paid bill must not nag"

    dispatch_reminders!
    assert_equal first_run.size, fake_sidecar.messages_to(s.jid).size,
                 "the same day's re-dispatch is a no-op (period_key dedup + claim)"
  end

  # NT-X-01 flavored for reminders: the pack yields exactly 4 events, the cap delivers 3.
  # "The cap throttles push, never truth" — every event still lands a dashboard row.
  test "the daily cap holds inside one sweep: 4 events, 3 pushes, 4 dashboard rows" do
    s = push_ready(E2E::Scenario.build(:reminders_due))

    dispatch_reminders!

    assert_equal 3, fake_sidecar.messages_to(s.jid).size, "DAILY_WA_CAP inside a single sweep"
    assert_equal 4, Notification.where(user: s.owner).count,
                 "all 4 events (Condomínio/Luz/card-closing/Freela) get a dashboard row; only Água is silent"
    assert_equal 3, Notification.where(user: s.owner).where.not(whatsapp_sent_at: nil).count,
                 "exactly 3 carry whatsapp_sent_at — the 4th is dashboard-only"
    assert_equal 1, Notification.where(user: s.owner, whatsapp_sent_at: nil).count,
                 "the capped event's row exists but never sent"
  end

  private

  def push_ready(s)
    s.wa_verified!(consent: true)
    s.owner.notification_prefs.update!(wa_intro_sent_at: Time.current)
    wa_connect!
    s
  end

  def fixed_bill(s, name, cents, due:)
    s.account.commitments.create!(
      kind: "fixed", name: name, bank_account: s.itau, category: s.category("Contas"),
      amount_cents: cents, starts_on: Date.current.beginning_of_month, schedule_day: due.day,
      created_by: s.owner)
  end

  def dispatch_reminders!
    Reminders::DailyDispatchJob.perform_now
    drain_jobs!
  end
end
