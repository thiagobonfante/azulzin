require "test_helper"

class NotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", onboarded_at: Time.current)
  end

  test "requires authentication" do
    get notification_preferences_url
    assert_redirected_to new_session_url
  end

  test "show renders the lazy defaults without creating a row" do
    sign_in_as(@user)
    assert_no_difference -> { NotificationPreference.count } do
      get notification_preferences_url
    end
    assert_response :success
  end

  test "update creates the row on first save and persists the choices" do
    sign_in_as(@user)
    assert_difference -> { NotificationPreference.count } => 1 do
      patch notification_preferences_url, params: { notification_preference: {
        whatsapp_consent: "1", weekly_summary: "1", bill_reminders: "0",
        bill_reminder_lead_days: "3", quiet_hours_start: "22", quiet_hours_end: "7",
        budget_warn_percent: "75", budget_breach_percent: "110"
      } }
    end
    assert_redirected_to notification_preferences_path

    prefs = @user.reload.notification_preference
    assert prefs.whatsapp_consent?
    assert prefs.weekly_summary?
    assert_not prefs.bill_reminders?
    assert_equal 3,   prefs.bill_reminder_lead_days
    assert_equal 22,  prefs.quiet_hours_start
    assert_equal 7,   prefs.quiet_hours_end
    assert_equal 75,  prefs.budget_warn_percent
    assert_equal 110, prefs.budget_breach_percent
  end

  test "invalid tuning re-renders with 422 and saves nothing" do
    sign_in_as(@user)
    assert_no_difference -> { NotificationPreference.count } do
      patch notification_preferences_url, params: { notification_preference: { bill_reminder_lead_days: "9" } }
    end
    assert_response :unprocessable_entity
  end
end
