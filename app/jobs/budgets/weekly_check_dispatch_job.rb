module Budgets
  # The weekly fan-out (recurring.yml `budgets_weekly_check`, Monday 11:00 UTC ⇒ 08:00 SP):
  # one pluck over memberships → one NotifyMemberJob per (account, member) — the exact
  # Reminders::DailyDispatchJob shape. Budgets are ACCOUNT data checked per MEMBER (each
  # member's own bands and toggles apply). Weekly, never per-transaction: no cost on the
  # write path (03 §4; D6). Plain ids at enqueue.
  class WeeklyCheckDispatchJob < ApplicationJob
    queue_as :default

    def perform
      as_of = Date.current   # SP (app TZ) at DISPATCH time — a member job drained late still keys this day
      pairs = AccountMembership.pluck(:account_id, :user_id)
      pairs.each { |account_id, user_id| NotifyMemberJob.perform_later(account_id, user_id, as_of) }
      Rails.logger.info("budgets_weekly_check: enqueued #{pairs.size} member checks")
    end
  end
end
