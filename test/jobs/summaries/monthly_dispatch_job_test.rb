require "test_helper"

class Summaries::MonthlyDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  test "fans out one NotifyMemberJob per membership, with plain ids, the monthly period and as_of" do
    travel_to Time.utc(2026, 8, 1, 11, 0)   # 08:00 SP on the 1st — the dispatch moment
    assert_enqueued_jobs AccountMembership.count, only: Summaries::NotifyMemberJob do
      Summaries::MonthlyDispatchJob.perform_now
    end
    assert_enqueued_with(job: Summaries::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id, "monthly", Date.new(2026, 8, 1) ])
  end
end
