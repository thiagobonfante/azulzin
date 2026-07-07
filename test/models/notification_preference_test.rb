require "test_helper"

class NotificationPreferenceTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  def prefs_with(**attrs)
    NotificationPreference.new(user: @user, **attrs)
  end

  test "defaults: dashboard kinds on, summaries + WhatsApp consent off, 1-day lead, 21–8 quiet, 80/100 bands" do
    prefs = prefs_with

    assert prefs.bill_reminders?
    assert prefs.budget_alerts?
    assert prefs.surplus_nudges?
    assert_not prefs.weekly_summary?
    assert_not prefs.monthly_summary?
    assert_not prefs.whatsapp_consent?, "proactive WhatsApp must be opt-in (ADR 0011)"
    assert_equal 1,   prefs.bill_reminder_lead_days
    assert_equal 21,  prefs.quiet_hours_start
    assert_equal 8,   prefs.quiet_hours_end
    assert_equal 80,  prefs.budget_warn_percent
    assert_equal 100, prefs.budget_breach_percent
  end

  test "lead days must be 0..7" do
    assert prefs_with(bill_reminder_lead_days: 0).valid?
    assert prefs_with(bill_reminder_lead_days: 7).valid?
    assert_not prefs_with(bill_reminder_lead_days: 8).valid?
    assert_not prefs_with(bill_reminder_lead_days: -1).valid?
  end

  test "quiet hours must be 0..23" do
    assert prefs_with(quiet_hours_start: 0, quiet_hours_end: 23).valid?
    assert_not prefs_with(quiet_hours_start: 24).valid?
    assert_not prefs_with(quiet_hours_end: -1).valid?
  end

  test "budget bands must be sensible percents (1..200, integers)" do
    assert prefs_with(budget_warn_percent: 50, budget_breach_percent: 110).valid?
    assert_not prefs_with(budget_warn_percent: 0).valid?
    assert_not prefs_with(budget_breach_percent: 201).valid?
    assert_not prefs_with(budget_warn_percent: 80.5).valid?
  end

  test "User#notification_prefs builds an unsaved default when no row exists (no backfill)" do
    prefs = @user.notification_prefs

    assert prefs.new_record?
    assert_no_difference -> { NotificationPreference.count } do
      @user.notification_prefs
    end
    assert_same prefs, @user.notification_prefs, "the built default is memoized on the association"
  end

  test "User#notification_prefs persists on first save and returns the row afterwards" do
    assert_difference -> { NotificationPreference.count } => 1 do
      @user.notification_prefs.update!(whatsapp_consent: true)
    end

    reloaded = User.find(@user.id).notification_prefs
    assert reloaded.persisted?
    assert reloaded.whatsapp_consent?
  end
end
