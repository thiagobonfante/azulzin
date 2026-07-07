require "test_helper"

class Budgets::WeeklyCheckDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fans out one NotifyMemberJob per membership, with plain ids" do
    assert_enqueued_jobs AccountMembership.count, only: Budgets::NotifyMemberJob do
      Budgets::WeeklyCheckDispatchJob.perform_now
    end
    assert_enqueued_with(job: Budgets::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id ])
  end
end
