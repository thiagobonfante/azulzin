# The "Avisos" settings screen (.plans/up-tier 01 §2): per-kind toggles, tuning, and the
# ONE master WhatsApp consent switch. Preferences are per member (not per account) — every
# member tunes their own. The row is created lazily on first save (no backfill).
class NotificationPreferencesController < AppController
  def show
    @preference = Current.user.notification_prefs
  end

  def update
    @preference = Current.user.notification_prefs
    if @preference.update(preference_params)
      redirect_to notification_preferences_path, notice: t(".saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def preference_params
      params.expect(notification_preference: %i[whatsapp_consent bill_reminders budget_alerts
                                                surplus_nudges weekly_summary monthly_summary
                                                bill_reminder_lead_days quiet_hours_start
                                                quiet_hours_end budget_warn_percent
                                                budget_breach_percent])
    end
end
