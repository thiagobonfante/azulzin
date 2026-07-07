module Summaries
  # One member's periodic digest (up-tier 04 §2): build the recap from the shared read
  # models and record it as this member's Notification row, then hand it to
  # Notifications::Deliver. The opt-in toggle is checked HERE, not just in Deliver:
  # summaries are pure push (default false) and a dashboard row for an opted-out member
  # is exactly the "opt-out surprise" 04 §4 bans — no row at all. period_key (the week's
  # Monday / the month's first) makes re-runs dedupe by construction. Serialized per USER
  # across ALL proactive notify jobs via the shared "proactive_notify" concurrency group
  # (Solid Queue scopes the semaphore per `group:`, default class name) so Deliver's
  # daily-cap read-then-act stays race-free when reminders, budgets, and summaries
  # coincide. as_of pins the window and period_key to the DISPATCH moment (SP): a weekly
  # run drained past Sunday midnight still files under the dispatched week's Monday.
  # Defaults to Date.current for manual/console runs.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, group: "proactive_notify", key: ->(_account_id, user_id, *) { user_id }

    discard_on ActiveRecord::RecordNotFound   # account or user deleted between enqueue and run

    # The period job-arg resolves through this map only — never reflection on raw input.
    TOGGLES = { "weekly" => "weekly_summary?", "monthly" => "monthly_summary?" }.freeze

    def perform(account_id, user_id, period, as_of = Date.current)
      toggle  = TOGGLES.fetch(period)
      account = Account.find(account_id)
      user    = User.find(user_id)
      return unless user.account == account                    # membership revoked mid-flight
      return unless user.notification_prefs.public_send(toggle)

      result = Build.call(account, period.to_sym, as_of: as_of)
      return unless result                                     # 04 §4: no empty summary, no row
      Notifications::Deliver.call(
        Notification.record!(user: user, account: account, kind: "#{period}_summary", **result))
    end
  end
end
