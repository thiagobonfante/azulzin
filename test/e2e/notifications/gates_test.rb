require "test_helpers/e2e/pipeline_case"

# NT-G: the universal gate matrix (.plans/e2e/04 §2). Every proactive kind rides the same
# Deliver chain — toggle → consent → channel → quiet hours → daily cap → atomic claim —
# and each gate fails CLOSED. Summary kinds render composite lines, so they join the
# blocked-gate cases here and deliver end-to-end in the summaries suite.
class E2E::NotificationGatesTest < E2E::PipelineCase
  ALL_KINDS  = Notifications::KINDS.keys
  RENDERABLE = ALL_KINDS - Notifications::SUMMARY_KINDS

  PAYLOADS = {
    "bill_due"         => { name: "Condomínio", amount_cents: 48_000, days_until: 1 },
    "bill_overdue"     => { name: "Luz", amount_cents: 18_500, days_overdue: 2 },
    "card_closing"     => { card: "Nubank", amount_cents: 25_000, days_until: 1 },
    "card_due"         => { card: "Nubank", amount_cents: 25_000, days_until: 2 },
    "income_expected"  => { name: "Salário", amount_cents: 500_000, days_until: 1 },
    "budget_warn"      => { category: "Mercado", spent_cents: 132_500, budget_cents: 150_000, left_cents: 17_500 },
    "budget_breach"    => { category: "Restaurantes", spent_cents: 64_780, budget_cents: 60_000 },
    "surplus_nudge"    => { surplus_cents: 42_000 },
    "rightsize_budget" => { category: "Vestuário", budget_cents: 100_000, typical_cents: 42_000 },
    "goal_alert"       => { finding: "pace", goal: "Carro", gap_cents: 30_000 },
    "goal_achieved"    => { goal: "Carro", amount_cents: 2_000_000 },
    "weekly_summary"   => {},
    "monthly_summary"  => {}
  }.freeze

  # NT-G-01
  test "every renderable kind delivers when all gates are open" do
    RENDERABLE.each do |kind|
      s = ready(kind)
      assert Notifications::Deliver.call(record!(s, kind)), "#{kind} must deliver"
      body = assert_wa_reply(s.jid)
      assert_match(/R\$/, body, "#{kind} must carry formatted money") unless kind == "goal_alert"
      assert_equal body, WhatsappMessage.outbound.order(:id).last.body
    end
  end

  # NT-G-02
  test "the kind's toggle off means dashboard-only, for every kind" do
    ALL_KINDS.each do |kind|
      s = ready(kind, toggle_on: false)
      n = record!(s, kind)
      assert_not Notifications::Deliver.call(n), "#{kind} must not push with its toggle off"
      assert_nil n.reload.whatsapp_sent_at
      assert_no_wa_reply(s.jid)
    end
  end

  # NT-G-03 — consent is the master switch and defaults FALSE
  test "no consent (the default) means dashboard-only, for every kind" do
    ALL_KINDS.each do |kind|
      s = ready(kind, consent: false)
      n = record!(s, kind)
      assert_not Notifications::Deliver.call(n)
      assert_nil n.reload.whatsapp_sent_at
      assert_no_wa_reply(s.jid)
    end
  end

  # NT-G-04
  test "unverified phone or missing JID means dashboard-only" do
    s = E2E::Scenario.build(:solo_basic)   # never verified
    s.owner.notification_prefs.update!(whatsapp_consent: true)
    wa_connect!
    assert_not Notifications::Deliver.call(record!(s, "bill_due"))
    assert_no_wa_reply(s.jid)
  end

  # NT-G-05
  test "sidecar disconnected means dashboard-only with the claim intact for the next sweep" do
    s = ready("bill_due")
    wa_disconnect!
    n = record!(s, "bill_due")
    assert_not Notifications::Deliver.call(n)
    assert_nil n.reload.whatsapp_sent_at, "the claim must NOT be burned while the channel is down"

    wa_connect!
    assert Notifications::Deliver.call(n), "the next sweep re-offers the same row"
    assert_wa_reply(s.jid)
  end

  # NT-G-06 — quiet hours default 21→08 SP, wrap-midnight, edges exact
  test "quiet hours suppress at 21:30 and 07:59 SP and release at 08:00 SP" do
    { Time.utc(2026, 5, 21, 0, 30) => false,    # 21:30 SP
      Time.utc(2026, 5, 21, 10, 59) => false,   # 07:59 SP
      Time.utc(2026, 5, 21, 11, 0) => true }.each do |at, delivered|
      s = ready("bill_due")
      travel_to at
      assert_equal delivered, Notifications::Deliver.call(record!(s, "bill_due")),
                   "at #{at.utc} delivery should be #{delivered}"
    end
  end

  # NT-G-07
  test "the daily cap stops the 4th push across kinds and re-arms the next SP day" do
    s = ready("bill_due")
    %w[bill_due bill_overdue card_closing].each do |kind|
      assert Notifications::Deliver.call(record!(s, kind))
    end

    fourth = record!(s, "budget_warn")
    assert_not Notifications::Deliver.call(fourth), "the 4th push of the day must hold"
    assert fourth.reload.whatsapp_sent_at.nil?
    assert_equal 3, fake_sidecar.messages_to(s.jid).size

    travel 1.day
    assert Notifications::Deliver.call(fourth), "the cap re-arms the next day"
  end

  # NT-G-08
  test "record! dedups on (user, kind, subject, period_key) and the claim sends once" do
    s = ready("budget_warn")
    a = record!(s, "budget_warn", period_key: Date.current.beginning_of_week)
    b = record!(s, "budget_warn", period_key: Date.current.beginning_of_week)
    assert_equal a.id, b.id, "a re-run must land on the same row"

    assert Notifications::Deliver.call(a)
    assert_not Notifications::Deliver.call(b), "the second delivery loses the atomic claim"
    assert_equal 1, fake_sidecar.messages_to(s.jid).size
  end

  # NT-G-10 — the one-time opt-out courtesy
  test "only the first-ever delivered push carries the responda parar footer" do
    s = ready("bill_due", intro_sent: false)
    footer = I18n.t("whatsapp.replies.notifications_footer", locale: :"pt-BR")

    Notifications::Deliver.call(record!(s, "bill_due"))
    assert_includes fake_sidecar.messages_to(s.jid).last.body, footer

    Notifications::Deliver.call(record!(s, "bill_overdue"))
    assert_not_includes fake_sidecar.messages_to(s.jid).last.body, footer
  end

  # NT-G-11 — fail-closed: a dead sidecar never crashes the sweep nor duplicates later
  test "a dead sidecar mid-send neither raises nor double-sends on re-delivery" do
    s = ready("bill_due")
    fake_sidecar.down!
    n = record!(s, "bill_due")

    assert_nothing_raised { Notifications::Deliver.call(n) }
    fake_sidecar.reset!
    wa_connect!
    assert_not Notifications::Deliver.call(n), "the claim was burned — lost, never duplicated"
    assert_no_wa_reply(s.jid)
  end

  # NT-X-03 — per-RECIPIENT locale at render time, BRL symbol pinned (never $)
  test "an en-US recipient gets en-US copy with the money still in R$" do
    s = ready("budget_warn")
    s.owner.update!(locale: "en-US")

    assert Notifications::Deliver.call(record!(s, "budget_warn"))

    # en-US currency format is %u%n (no space) — pinned as-is; change the locale file if
    # the spaced form is preferred.
    assert_wa_reply s.jid,
      equals: "👀 *Mercado* is at R$1,325.00 of R$1,500.00 this month. R$175.00 to go."
  end

  # NT-G-12
  test "couple: each member gets their own row and their own push, toggles independent" do
    s = E2E::Scenario.build(:couple)
    wa_connect!
    s.members.each { |m| m.notification_prefs.update!(whatsapp_consent: true) }
    s.partner.notification_prefs.update!(bill_reminders: false)

    s.members.each do |m|
      Notifications::Deliver.call(
        Notification.record!(user: m, account: s.account, kind: "bill_due",
                             period_key: Date.current, payload: PAYLOADS["bill_due"]))
    end

    assert_equal 1, fake_sidecar.messages_to(s.jid(s.owner)).size
    assert_no_wa_reply(s.jid(s.partner))
    assert_equal 2, Notification.where(account: s.account, kind: "bill_due").count,
                 "both dashboards get the row regardless of the push toggle"
  end

  private

  # A scenario wired for the kind: verified, consented, toggle set, sidecar connected,
  # intro footer already spent (goldens elsewhere stay footer-free).
  def ready(kind, consent: true, toggle_on: true, intro_sent: true)
    s = E2E::Scenario.build(:solo_basic).wa_verified!(consent: consent)
    s.owner.notification_prefs.update!(
      Notifications::KINDS.fetch(kind).fetch(:toggle) => toggle_on,
      wa_intro_sent_at: (Time.current if intro_sent))
    wa_connect!
    s
  end

  # period_key is a DATE column; a unique date per call keeps matrix rows distinct.
  def record!(s, kind, period_key: Date.current + E2E::Seq.next)
    Notification.record!(user: s.owner, account: s.account, kind: kind,
                         period_key: period_key, payload: PAYLOADS.fetch(kind))
  end
end
