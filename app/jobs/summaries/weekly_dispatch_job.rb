module Summaries
  # The weekly digest fan-out (recurring.yml `summaries_weekly`, Sunday 23:00 UTC ⇒
  # 20:00 SP — end-of-week, before the week resets): one pluck over memberships → one
  # NotifyMemberJob per (account, member), the exact Reminders::DailyDispatchJob shape.
  # Plain ids at enqueue: no AR objects, nothing to load inside a concurrency-key lambda.
  class WeeklyDispatchJob < ApplicationJob
    queue_as :default

    def perform
      as_of = Date.current   # SP (app TZ) at DISPATCH time — a member job drained past midnight still files this week
      pairs = AccountMembership.pluck(:account_id, :user_id)
      pairs.each { |account_id, user_id| NotifyMemberJob.perform_later(account_id, user_id, "weekly", as_of) }
      Rails.logger.info("summaries_weekly: enqueued #{pairs.size} member digests")
    end
  end
end
