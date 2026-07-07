module Reminders
  # One member's daily reminder sweep: scan the account over [today, today + their
  # lead-days] (SP-time) and record each event as this member's Notification row, then hand
  # it to Notifications::Deliver — dashboard-only in this phase; Phase 3 turns the push on.
  # Re-runs are free: period_key = the event's date, so Notification.record! dedupes.
  # Serialized per USER (mirrors ProcessInboundWhatsappJob) so Deliver's daily-cap
  # read-then-act stays race-free when the push channel exists.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, key: ->(_account_id, user_id) { user_id }

    discard_on ActiveRecord::RecordNotFound   # account or user deleted between enqueue and run

    def perform(account_id, user_id)
      account = Account.find(account_id)
      user    = User.find(user_id)
      return unless user.account == account          # membership revoked mid-flight (02 §6)

      prefs = user.notification_prefs
      return unless prefs.bill_reminders?            # the one toggle gating every F1 kind

      today = Date.current.in_time_zone("America/Sao_Paulo").to_date
      Scan.call(account, from: today, to: today + prefs.bill_reminder_lead_days).each do |event|
        Notifications::Deliver.call(Notification.record!(user: user, account: account, **event))
      end
    end
  end
end
