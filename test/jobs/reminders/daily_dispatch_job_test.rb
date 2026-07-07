require "test_helper"

class Reminders::DailyDispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  test "fans out one NotifyMemberJob per membership, with plain ids and the dispatch-time as_of" do
    travel_to Time.utc(2026, 7, 7, 15, 0)   # 12:00 SP
    assert_enqueued_jobs AccountMembership.count, only: Reminders::NotifyMemberJob do
      Reminders::DailyDispatchJob.perform_now
    end
    assert_enqueued_with(job: Reminders::NotifyMemberJob,
                         args: [ accounts(:confirmed).id, users(:confirmed).id, Date.new(2026, 7, 7) ])
  end
end
