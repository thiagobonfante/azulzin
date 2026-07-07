module Reminders
  # The daily fan-out (recurring.yml `reminders_daily_dispatch`, 11:00 UTC ⇒ 08:00 SP):
  # one pluck over memberships → one NotifyMemberJob per (account, member). Reminders are
  # ACCOUNT data delivered per MEMBER (up-tier 07 D8: every member with the toggle on gets
  # their own row, computed at their own lead-days) — and iterating memberships is also the
  # "no reminder for someone who can't see the account" guarantee (02 §6). Plain ids at
  # enqueue: no AR objects, nothing to load inside a concurrency-key lambda.
  class DailyDispatchJob < ApplicationJob
    queue_as :default

    def perform
      as_of = Date.current   # SP (app TZ) at DISPATCH time — a member job drained late still keys this day
      pairs = AccountMembership.pluck(:account_id, :user_id)
      pairs.each { |account_id, user_id| NotifyMemberJob.perform_later(account_id, user_id, as_of) }
      Rails.logger.info("reminders_daily_dispatch: enqueued #{pairs.size} member scans")
    end
  end
end
