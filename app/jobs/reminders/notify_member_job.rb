module Reminders
  # One member's daily reminder sweep: scan the account over [as_of, as_of + their
  # lead-days] (SP-time) and record each event as this member's Notification row, then hand
  # it to Notifications::Deliver — dashboard-only in this phase; Phase 3 turns the push on.
  # Re-runs are free: period_key = the event's date, so Notification.record! dedupes.
  # Serialized per USER across ALL proactive notify jobs — Solid Queue scopes the semaphore
  # per `group:` (default: the class name), so the shared "proactive_notify" group is what
  # keeps Deliver's daily-cap read-then-act race-free when reminders, budgets, and
  # summaries coincide (Monday the 1st).
  # as_of pins "today" to the DISPATCH moment (SP): a run delayed past midnight still
  # scans and keys the dispatched day. Defaults to Date.current for manual/console runs.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, group: "proactive_notify", key: ->(_account_id, user_id, *) { user_id }

    discard_on ActiveRecord::RecordNotFound   # account or user deleted between enqueue and run

    def perform(account_id, user_id, as_of = Date.current)
      account = Account.find(account_id)
      user    = User.find(user_id)
      return unless user.account == account          # membership revoked mid-flight (02 §6)

      prefs = user.notification_prefs
      return unless prefs.bill_reminders?            # the one toggle gating every F1 kind

      Scan.call(account, from: as_of, to: as_of + prefs.bill_reminder_lead_days).each do |event|
        Notifications::Deliver.call(Notification.record!(user: user, account: account, **event))
      end
    end
  end
end
