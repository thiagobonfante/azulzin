require "test_helper"

# Gate + send tests for the one send policy (up-tier 01 §3). Phase 3 posture (ADR 0011
# signed): the push is live — the atomic fail-closed claim referees concurrency, every
# send is a logged WhatsappMessage rendered in the recipient's locale, and the first-ever
# push carries the one-time opt-out footer.
class Notifications::DeliverTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    # A fully push-ready member: verified ownership + captured JID + explicit consent +
    # a live sidecar. The intro footer is already spent (its own tests reset it); each
    # gate test below breaks exactly one gate.
    @user.update!(phone: "5511912345678", phone_verified_at: Time.current,
                  whatsapp_id: "5511912345678", whatsapp_jid: "5511912345678@c.us")
    @user.notification_prefs.update!(whatsapp_consent: true, wa_intro_sent_at: 1.week.ago)
    WhatsappConnection.instance.update!(status: "connected")
    travel_to Time.utc(2026, 7, 7, 15, 0)   # 12:00 in São Paulo — outside quiet hours
  end

  BILL_PAYLOAD = { "name" => "Luz", "amount_cents" => 18_240,
                   "due_on" => "2026-07-08", "days_until" => 1 }.freeze

  def notification(kind: "bill_due", period_key: Date.new(2026, 7, 8), payload: BILL_PAYLOAD, **overrides)
    Notification.record!(user: @user, account: @account, kind: kind, period_key: period_key,
                         payload: payload, **overrides)
  end

  def deliver(n) = Notifications::Deliver.new(n)

  # Runs the block with the sidecar wire stubbed, collecting each outbound body.
  def capture_sends(&block)
    bodies = []
    WhatsappService.stub(:send_message, ->(_to, body) { bodies << body; { id: "out-#{SecureRandom.hex(3)}" } }, &block)
    bodies
  end

  test "all gates pass → ONE outbound WhatsappMessage, claim stamped, localized body with money" do
    n = notification
    bodies = nil
    assert_difference -> { WhatsappMessage.count }, 1 do
      bodies = capture_sends { assert Notifications::Deliver.call(n), "a real push reports true" }
    end
    assert_not_nil n.reload.whatsapp_sent_at, "the claim is stamped by the send"
    assert_includes bodies.sole, "*Luz*"
    assert_includes bodies.sole, "R$ 182,40", "money is pre-formatted by Ruby, in pt-BR"
    assert_includes bodies.sole, "vence amanhã", "days_until drives the plural branch"
  end

  test "claim race: two deliveries for one notification → exactly ONE outbound message" do
    n = notification
    assert_difference -> { WhatsappMessage.count }, 1 do
      capture_sends do
        assert Notifications::Deliver.call(n)
        assert_not Notifications::Deliver.call(n), "the loser's update_all matches zero rows"
      end
    end
  end

  test "a pre-claimed notification never sends again (update_all on the nil claim)" do
    n = notification
    n.update!(whatsapp_sent_at: Time.current)
    assert_no_difference -> { WhatsappMessage.count } do
      capture_sends { assert_not Notifications::Deliver.call(n) }
    end
  end

  test "an en-US recipient gets the en template, money still in reais" do
    @user.update!(locale: "en-US")
    bodies = capture_sends { Notifications::Deliver.call(notification) }
    assert_includes bodies.sole, "is due tomorrow", "I18n.with_locale(user.locale) picks en"
    assert bodies.sole.match?(/R\$\s?\d/), "reais never render as dollars"
  end

  test "a REAL scanner event round-trips: Scan (symbol keys) → record! → push renders" do
    inst = Institution.find_by(code: "260")
    card = CreditCard.create!(account: @account, institution: inst,
                              bill_due_day: 10, closing_offset_days: 2)   # July fatura closes 07-08
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 12_300,
                                  occurred_on: Date.new(2026, 7, 1), credit_card: card)
    event = Reminders::Scan.call(@account, from: Date.new(2026, 7, 7), to: Date.new(2026, 7, 8)).sole
    assert_equal "card_closing", event[:kind]

    bodies = capture_sends do
      assert Notifications::Deliver.call(
        Notification.record!(user: @user, account: @account, **event))
    end
    assert_includes bodies.sole, "fecha amanhã", "the scanner payload templates without a DB round-trip"
    assert_includes bodies.sole, "R$ 123,00"
  end

  CARD_DUE_PAYLOAD = { "card" => "Nubank", "amount_cents" => 234_056,
                       "date" => "2026-07-10", "days_until" => 1 }.freeze

  test "the first-ever push carries the opt-out footer; the second doesn't" do
    @user.notification_prefs.update!(wa_intro_sent_at: nil)
    bodies = capture_sends do
      Notifications::Deliver.call(notification)
      Notifications::Deliver.call(notification(kind: "card_due", period_key: Date.new(2026, 7, 10),
                                               payload: CARD_DUE_PAYLOAD))
    end
    assert_equal 2, bodies.size
    assert_includes bodies.first, "*parar*", "first push teaches the opt-out once"
    assert_not_includes bodies.second, "parar", "no repeated boilerplate"
    assert_not_nil @user.notification_prefs.reload.wa_intro_sent_at, "the stamp is spent by the send"
  end

  test "a failed send does not burn the intro footer — the next delivered push teaches parar" do
    @user.notification_prefs.update!(wa_intro_sent_at: nil)
    WhatsappService.stub(:send_message, ->(*) { raise IOError, "sidecar hiccup" }) do
      assert_raises(IOError) { Notifications::Deliver.call(notification) }
    end
    assert_nil @user.notification_prefs.reload.wa_intro_sent_at,
               "the stamp lands only AFTER a successful send"

    bodies = capture_sends do
      Notifications::Deliver.call(notification(kind: "card_due", period_key: Date.new(2026, 7, 10),
                                               payload: CARD_DUE_PAYLOAD))
    end
    assert_includes bodies.sole, "*parar*", "the first DELIVERED push still carries the courtesy"
    assert_not_nil @user.notification_prefs.reload.wa_intro_sent_at
  end

  test "kind toggle off → no push (gates both channels' push, dashboard row remains)" do
    @user.notification_prefs.update!(bill_reminders: false)
    assert_not deliver(notification).push_allowed?
  end

  test "the toggle is resolved per kind through the registry" do
    @user.notification_prefs.update!(budget_alerts: false)
    assert_not deliver(notification(kind: "budget_breach")).push_allowed?
    assert deliver(notification(kind: "bill_due")).push_allowed?, "bill kinds ride a different toggle"
  end

  test "no whatsapp consent (the default) → no push" do
    @user.notification_prefs.update!(whatsapp_consent: false)
    assert_not deliver(notification).push_allowed?
  end

  test "consent without a persisted preferences row is impossible — defaults stay silent" do
    @user.notification_preference.destroy!
    @user.reload   # drop the cached (destroyed) association target
    assert_not deliver(notification).push_allowed?, "lazy defaults have whatsapp_consent false"
  end

  test "unverified phone → no push (ownership gate)" do
    @user.update!(phone_verified_at: nil)
    assert_not deliver(notification).push_allowed?
  end

  test "missing captured JID → no push (bare phone may not reach @lid contacts)" do
    @user.update!(whatsapp_jid: nil)
    assert_not deliver(notification).push_allowed?
  end

  test "sidecar disconnected → no send, the claim is NOT burned, the dashboard row is intact" do
    WhatsappConnection.instance.update!(status: "disconnected")
    n = notification

    assert_no_difference -> { WhatsappMessage.count } do
      assert_not Notifications::Deliver.call(n)
    end
    assert_nil n.reload.whatsapp_sent_at
    assert_includes Notification.dashboard_for(@user, @account), n
  end

  test "quiet hours wrap midnight in São Paulo time" do
    travel_to Time.utc(2026, 7, 8, 2, 0)     # 23:00 SP — quiet
    assert_not deliver(notification).push_allowed?

    travel_to Time.utc(2026, 7, 8, 10, 30)   # 07:30 SP — still quiet
    assert_not deliver(notification).push_allowed?

    travel_to Time.utc(2026, 7, 8, 12, 0)    # 09:00 SP — allowed again
    assert deliver(notification).push_allowed?
  end

  test "equal quiet-hours bounds mean an empty window, never all-day silence" do
    @user.notification_prefs.update!(quiet_hours_start: 9, quiet_hours_end: 9)
    travel_to Time.utc(2026, 7, 8, 12, 0)    # 09:00 SP
    assert deliver(notification).push_allowed?
  end

  test "over the daily cap (3 claims today SP) → no push; yesterday's claims don't count" do
    claim = lambda do |kind, sent_at|
      Notification.create!(user: @user, account: @account, kind: kind,
                           period_key: Date.new(2026, 7, 1), whatsapp_sent_at: sent_at)
    end
    claim.call("budget_warn", 30.hours.ago)   # yesterday SP — doesn't count
    claim.call("budget_breach", Time.current)
    claim.call("card_due", Time.current)
    assert deliver(notification).push_allowed?, "two claims today is under the cap"

    claim.call("weekly_summary", Time.current)   # summaries are counted too
    assert_not deliver(notification).push_allowed?
    assert_no_difference -> { WhatsappMessage.count } do
      assert_not Notifications::Deliver.call(notification), "over the cap → dashboard-only"
    end
  end

  test "quiet hours → dashboard-only, nothing sent and no claim burned" do
    travel_to Time.utc(2026, 7, 8, 2, 0)     # 23:00 SP — quiet
    n = notification
    assert_no_difference -> { WhatsappMessage.count } do
      assert_not Notifications::Deliver.call(n)
    end
    assert_nil n.reload.whatsapp_sent_at
  end
end
