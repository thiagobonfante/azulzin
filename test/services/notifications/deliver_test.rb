require "test_helper"

# Gate tests for the one send policy (up-tier 01 §3). Phase 0 posture: even when every
# gate passes, NOTHING is sent and no claim is burned — the send step is inert until
# Phase 3 (ADR 0011 dashboard-only soak).
class Notifications::DeliverTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    # A fully push-ready member: verified ownership + captured JID + explicit consent +
    # a live sidecar. Each test below breaks exactly one gate.
    @user.update!(phone: "5511912345678", phone_verified_at: Time.current,
                  whatsapp_id: "5511912345678", whatsapp_jid: "5511912345678@c.us")
    @user.notification_prefs.update!(whatsapp_consent: true)
    WhatsappConnection.instance.update!(status: "connected")
    travel_to Time.utc(2026, 7, 7, 15, 0)   # 12:00 in São Paulo — outside quiet hours
  end

  def notification(kind: "bill_due", period_key: Date.new(2026, 7, 8), **overrides)
    Notification.record!(user: @user, account: @account, kind: kind, period_key: period_key, **overrides)
  end

  def deliver(n) = Notifications::Deliver.new(n)

  test "all gates pass → would push, but Phase 0 sends NOTHING and burns no claim" do
    n = notification
    assert deliver(n).push_allowed?, "every gate should pass for the push-ready member"

    assert_no_difference -> { WhatsappMessage.count } do
      assert_not Notifications::Deliver.call(n), "the inert send step reports no push"
    end
    assert_nil n.reload.whatsapp_sent_at, "the claim must not be burned while no send exists"
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

  test "sidecar disconnected → no push and the claim is NOT burned (next sweep covers it)" do
    WhatsappConnection.instance.update!(status: "disconnected")
    n = notification

    assert_not Notifications::Deliver.call(n)
    assert_nil n.reload.whatsapp_sent_at
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
    claim.call("card_bill", Time.current)
    assert deliver(notification).push_allowed?, "two claims today is under the cap"

    claim.call("weekly_summary", Time.current)   # summaries are counted too
    assert_not deliver(notification).push_allowed?
  end
end
