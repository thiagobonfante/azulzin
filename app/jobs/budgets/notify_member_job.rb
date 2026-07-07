module Budgets
  # One member's weekly budget sweep (up-tier 03 §4–5): warn/breach rows for the current
  # billing month at THEIR bands, then — only in the LAST WEEK of the month, so "sobra" is
  # real and not an early-month illusion — at most ONE under-budget suggestion (D9: surplus
  # preferred, else rightsize, or silence). Dashboard-only this phase; Phase 3 turns the
  # push on. Serialized per USER across ALL proactive notify jobs via the shared
  # "proactive_notify" concurrency group (Solid Queue scopes the semaphore per `group:`,
  # default class name) so Deliver's daily-cap read-then-act stays race-free when
  # reminders, budgets, and summaries coincide. as_of pins "today" to the DISPATCH moment
  # (SP); defaults to Date.current for manual/console runs.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, group: "proactive_notify", key: ->(_account_id, user_id, *) { user_id }

    discard_on ActiveRecord::RecordNotFound   # account or user deleted between enqueue and run

    # D9's one-per-month rule spans BOTH suggestion kinds — the dedup index can't referee
    # it (the kinds differ), so the job checks for either before picking.
    SUGGESTION_KINDS = %w[surplus_nudge rightsize_budget].freeze
    LAST_WEEK_DAYS   = 7

    def perform(account_id, user_id, as_of = Date.current)
      account = Account.find(account_id)
      user    = User.find(user_id)
      return unless user.account == account          # membership revoked mid-flight

      today = as_of
      month = today.beginning_of_month
      prefs = user.notification_prefs

      if prefs.budget_alerts?
        Check.call(account, month: month, warn_percent: prefs.budget_warn_percent,
                            breach_percent: prefs.budget_breach_percent).each do |event|
          Notifications::Deliver.call(Notification.record!(user: user, account: account, **event))
        end
      end

      return unless prefs.surplus_nudges? && last_week_of?(month, today)
      return if Notification.exists?(user: user, kind: SUGGESTION_KINDS, period_key: month)
      if (event = Suggestion.pick(account, month: month))
        Notifications::Deliver.call(Notification.record!(user: user, account: account, **event))
      end
    end

    private

    def last_week_of?(month, today) = today > month.end_of_month - LAST_WEEK_DAYS
  end
end
