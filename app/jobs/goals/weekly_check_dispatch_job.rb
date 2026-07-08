module Goals
  # The Monday fan-out (recurring.yml `goals_weekly_check`, 11:00 UTC ⇒ 08:00 SP — matching
  # budgets_weekly_check). One pluck over memberships of accounts WITH active goals → one
  # NotifyMemberJob per (account, member), the shipped Reminders/Budgets dispatch shape. Goals are
  # ACCOUNT data checked per MEMBER (each opted-in member gets the household's notifications). Plain
  # ids + as_of at enqueue so a late-drained job still keys the dispatch day. See .plans/goals 06 §2.
  class WeeklyCheckDispatchJob < ApplicationJob
    queue_as :default

    def perform
      as_of = Date.current
      account_ids = Goal.active.distinct.pluck(:account_id)
      pairs = AccountMembership.where(account_id: account_ids).pluck(:account_id, :user_id)
      pairs.each { |account_id, user_id| NotifyMemberJob.perform_later(account_id, user_id, as_of) }
      Rails.logger.info("goals_weekly_check: enqueued #{pairs.size} member checks")
    end
  end
end
