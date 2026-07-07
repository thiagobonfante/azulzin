require "test_helper"

class Budgets::WeeklyCheckDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  test "fans out one NotifyMemberJob per membership, with plain ids and the dispatch-time as_of" do
    travel_to Time.utc(2026, 7, 6, 15, 0)   # Monday 12:00 SP
    assert_enqueued_jobs AccountMembership.count, only: Budgets::NotifyMemberJob do
      Budgets::WeeklyCheckDispatchJob.perform_now
    end
    assert_enqueued_with(job: Budgets::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id, Date.new(2026, 7, 6) ])
  end
end
