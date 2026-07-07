require "test_helper"

class NotificationRetentionJobTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  def make_notification(kind, period_key)
    Notification.create!(user: @user, account: @user.account, kind: kind, period_key: period_key)
  end

  test "deletes only rows whose period_key is older than the window" do
    old    = make_notification("bill_due",    60.days.ago.to_date)
    edge   = make_notification("card_bill",   45.days.ago.to_date)
    recent = make_notification("budget_warn", Date.current)

    assert_equal 1, NotificationRetentionJob.new.perform

    assert_not Notification.exists?(old.id)
    assert Notification.exists?(edge.id), "the cutoff day itself is kept (strictly older-than)"
    assert Notification.exists?(recent.id)
  end

  test "the window is tunable per run" do
    ten_days = make_notification("bill_due", 10.days.ago.to_date)

    assert_equal 1, NotificationRetentionJob.new.perform(retain_days: 5)
    assert_not Notification.exists?(ten_days.id)
  end
end
