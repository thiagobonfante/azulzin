require "test_helpers/e2e/pipeline_case"

# NT-PU: the native push channel (.plans/mobile/04). One notification, one channel: a
# push-capable user's notification rides FCM; WhatsApp is the no-device default and the
# failed-send fallback. Push titles/bodies are pinned as full pt-BR goldens — discreet
# lock-screen copy, no amounts. The transport seam stands in for FCM (real HTTP is the
# only thing stubbed beyond the AI boundary).
class E2E::NotificationPushTest < E2E::PipelineCase
  BILL_PAYLOAD = { name: "Condomínio", amount_cents: 48_000, days_until: 1 }.freeze

  setup do
    @pushes = []
    @push_result = { ok: true }
    Notifications::PushSender.transport = ->(payload) { @pushes << payload; @push_result }
  end

  teardown { Notifications::PushSender.transport = nil }

  def ready(kind = "bill_due", consent: true)
    s = E2E::Scenario.build(:solo_basic).wa_verified!(consent: consent)
    s.owner.notification_prefs.update!(
      Notifications::KINDS.fetch(kind).fetch(:toggle) => true, wa_intro_sent_at: Time.current)
    wa_connect!
    s
  end

  def register_device!(s)
    session = s.owner.sessions.create!
    [ PushDevice.register!(token: "tok-#{s.owner.id}", user: s.owner,
                           session: session, platform: "ios"), session ]
  end

  def record!(s, kind = "bill_due", payload: BILL_PAYLOAD, period_key: Date.current + E2E::Seq.next)
    Notification.record!(user: s.owner, account: s.account, kind: kind,
                         period_key: period_key, payload: payload)
  end

  # NT-PU-01 — device registered → push claimed with golden copy, WhatsApp NOT sent
  test "a registered device claims the push and WhatsApp stays silent" do
    s = ready
    register_device!(s)
    n = record!(s)
    assert Notifications::Deliver.call(n)
    assert_not_nil n.reload.push_sent_at, "the push claim must be stamped"
    assert_nil n.whatsapp_sent_at, "one notification, one channel — WA must not claim"
    assert_no_wa_reply(s.jid)

    push = @pushes.sole[:message]
    assert_equal "tok-#{s.owner.id}", push[:token]
    assert_equal "Conta chegando", push[:notification][:title]
    assert_equal "Condomínio vence amanhã.", push[:notification][:body]
    assert_equal "/commitments", push[:data][:url]
  end

  # NT-PU-02 — no device → the WhatsApp path exactly as today (regression pin)
  test "no device keeps the WhatsApp path byte-identical" do
    s = ready
    n = record!(s)
    assert Notifications::Deliver.call(n)
    assert_nil n.reload.push_sent_at
    assert_not_nil n.whatsapp_sent_at
    assert_empty @pushes
    assert_wa_reply s.jid, equals: "🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙"
  end

  # NT-PU-03a — quiet hours block the push claim (shared gate, dashboard-only)
  test "quiet hours suppress the push with the claim intact" do
    s = ready
    register_device!(s)
    travel_to Time.utc(2026, 5, 21, 0, 30)   # 21:30 SP
    n = record!(s)
    assert_not Notifications::Deliver.call(n)
    assert_nil n.reload.push_sent_at
    assert_empty @pushes
    assert_no_wa_reply(s.jid)
  end

  # NT-PU-03b — the push daily cap holds the 4th, and a push-capable user never
  # channel-hops to WhatsApp (that would still nag) — dashboard-only past the cap.
  test "the push daily cap stops the 4th and does not spill into WhatsApp" do
    s = ready
    register_device!(s)
    %w[bill_due bill_overdue card_closing].each do |kind|
      payload = BILL_PAYLOAD.merge(card: "Nubank", days_overdue: 1)
      assert Notifications::Deliver.call(record!(s, kind, payload: payload))
    end
    assert_equal 3, @pushes.size

    fourth = record!(s, "card_due", payload: BILL_PAYLOAD.merge(card: "Nubank"))
    assert_not Notifications::Deliver.call(fourth), "the 4th push of the day must hold"
    assert_nil fourth.reload.push_sent_at
    assert_nil fourth.whatsapp_sent_at, "cap-blocked must NOT fall back to WhatsApp"
    assert_no_wa_reply(s.jid)

    travel 1.day
    assert Notifications::Deliver.call(fourth), "the cap re-arms the next SP day"
    assert_equal 4, @pushes.size
  end

  # NT-PU-04 — the in-app kill switch falls back to WhatsApp
  test "push_enabled off falls back to the WhatsApp channel" do
    s = ready
    register_device!(s)
    s.owner.notification_prefs.update!(push_enabled: false)
    n = record!(s)
    assert Notifications::Deliver.call(n)
    assert_empty @pushes
    assert_nil n.reload.push_sent_at
    assert_wa_reply s.jid, equals: "🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙"
  end

  # NT-PU-05 — sign-out destroys the session → device revoked → next fire goes WA
  test "destroying the session revokes the device and the next fire goes to WhatsApp" do
    s = ready
    _device, session = register_device!(s)
    session.destroy!
    assert_equal 0, s.owner.push_devices.count

    n = record!(s)
    assert Notifications::Deliver.call(n)
    assert_empty @pushes
    assert_wa_reply s.jid, equals: "🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙"
  end

  # NT-PU-06 — every device send failing burns the push claim and falls back to WA
  # (the burned claim is correct: this notification must never re-push).
  test "a failed send falls back to WhatsApp with the push claim burned" do
    s = ready
    register_device!(s)
    @push_result = { ok: false }
    n = record!(s)
    assert Notifications::Deliver.call(n)
    assert_not_nil n.reload.push_sent_at, "the claim burns even when the send fails"
    assert_not_nil n.whatsapp_sent_at
    assert_wa_reply s.jid, equals: "🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙"
  end
end
