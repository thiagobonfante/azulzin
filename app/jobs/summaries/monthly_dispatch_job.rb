module Summaries
  # The monthly digest fan-out (recurring.yml `summaries_monthly`, the 1st 11:00 UTC ⇒
  # 08:00 SP — recaps the month that just closed, SP-time): one pluck over memberships →
  # one NotifyMemberJob per (account, member). Plain ids at enqueue.
  class MonthlyDispatchJob < ApplicationJob
    queue_as :default

    def perform
      as_of = Date.current   # SP (app TZ) at DISPATCH time — a member job drained late still recaps the same closed month
      pairs = AccountMembership.pluck(:account_id, :user_id)
      pairs.each { |account_id, user_id| NotifyMemberJob.perform_later(account_id, user_id, "monthly", as_of) }
      Rails.logger.info("summaries_monthly: enqueued #{pairs.size} member digests")
    end
  end
end
