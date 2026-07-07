require "test_helper"

class Summaries::WeeklyDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  test "fans out one NotifyMemberJob per membership, with plain ids, the weekly period and as_of" do
    travel_to Time.utc(2026, 7, 12, 23, 0)   # Sunday 20:00 SP — the dispatch moment
    assert_enqueued_jobs AccountMembership.count, only: Summaries::NotifyMemberJob do
      Summaries::WeeklyDispatchJob.perform_now
    end
    assert_enqueued_with(job: Summaries::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id, "weekly", Date.new(2026, 7, 12) ])
  end
end
