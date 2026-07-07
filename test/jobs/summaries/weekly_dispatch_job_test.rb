require "test_helper"

class Summaries::WeeklyDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fans out one NotifyMemberJob per membership, with plain ids and the weekly period" do
    assert_enqueued_jobs AccountMembership.count, only: Summaries::NotifyMemberJob do
      Summaries::WeeklyDispatchJob.perform_now
    end
    assert_enqueued_with(job: Summaries::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id, "weekly" ])
  end
end
