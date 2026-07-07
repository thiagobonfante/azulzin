require "test_helper"

class Reminders::DailyDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fans out one NotifyMemberJob per membership, with plain ids" do
    assert_enqueued_jobs AccountMembership.count, only: Reminders::NotifyMemberJob do
      Reminders::DailyDispatchJob.perform_now
    end
    assert_enqueued_with(job: Reminders::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id ])
  end
end
