require "test_helper"

# The three proactive member jobs MUST share one per-user semaphore: Solid Queue scopes
# `limits_concurrency` per `group:` (default: the class name), so without a shared group
# the classes run concurrently for the same user and Deliver's daily-cap count-then-claim
# can exceed DAILY_WA_CAP when the 11am schedules coincide (Monday the 1st: reminders +
# budgets + monthly summaries).
class ProactiveNotifyConcurrencyTest < ActiveSupport::TestCase
  test "reminders, budgets and summaries notify jobs serialize on ONE per-user key" do
    keys = [ Reminders::NotifyMemberJob.new(1, 42),
             Budgets::NotifyMemberJob.new(1, 42),
             Summaries::NotifyMemberJob.new(1, 42, "weekly") ].map(&:concurrency_key)

    assert_equal 1, keys.uniq.size, "different keys = different semaphores = the cap can be blown"
    assert_equal "proactive_notify/42", keys.first, "the group must not default to the class name"
  end

  test "different users never share a semaphore" do
    assert_not_equal Reminders::NotifyMemberJob.new(1, 42).concurrency_key,
                     Budgets::NotifyMemberJob.new(1, 43).concurrency_key
  end
end
