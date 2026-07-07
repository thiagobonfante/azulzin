require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
  end

  def record!(**overrides)
    defaults = { user: @user, account: @account, kind: "bill_due", period_key: Date.new(2026, 7, 10) }
    Notification.record!(**defaults.merge(overrides))
  end

  test "record! is idempotent on the dedup keys — one row, snapshot untouched" do
    first  = record!(payload: { "amount_cents" => 18_240 })
    second = record!(payload: { "amount_cents" => 99_999 })

    assert_equal first.id, second.id
    assert_equal 1, Notification.where(user: @user, kind: "bill_due").count
    assert_equal 18_240, second.payload["amount_cents"], "a re-run must not clobber the payload snapshot"
  end

  test "a re-run never clobbers whatsapp_sent_at or dismissed_at (the goals lesson)" do
    row = record!
    row.update!(whatsapp_sent_at: 2.hours.ago, dismissed_at: 1.hour.ago)
    row.reload

    again = record!

    assert_equal row.id, again.id
    assert_equal row.whatsapp_sent_at, again.whatsapp_sent_at
    assert_equal row.dismissed_at, again.dismissed_at
  end

  test "different subject or period_key creates distinct rows" do
    category = @account.categories.create!(name: "Luz")

    base         = record!
    with_subject = record!(subject: category)
    other_period = record!(period_key: Date.new(2026, 8, 10))

    assert_equal 3, [ base.id, with_subject.id, other_period.id ].uniq.size
  end

  test "the unique index referees at the DB — subject-less kinds (summaries) included" do
    Notification.create!(user: @user, account: @account, kind: "weekly_summary", period_key: Date.new(2026, 7, 6))
    assert_raises(ActiveRecord::RecordNotUnique) do
      Notification.create!(user: @user, account: @account, kind: "weekly_summary", period_key: Date.new(2026, 7, 6))
    end
  end

  test "record! rescues a concurrent-insert race by loading the winner's row" do
    existing = record!
    raced    = false
    raiser   = lambda do |*_args, **_kwargs, &_blk|
      raced = true
      raise ActiveRecord::RecordNotUnique, "simulated race"
    end

    Notification.stub(:find_or_create_by!, raiser) do
      assert_equal existing.id, record!.id
    end
    assert raced, "the stub should have forced the rescue path"
  end

  test "rejects a kind missing from the registry" do
    assert_raises(ActiveRecord::RecordInvalid) { record!(kind: "carrier_pigeon") }
  end

  test "every registered kind maps to a real preference toggle" do
    prefs = NotificationPreference.new(user: @user)
    Notifications::KINDS.each_value do |entry|
      assert prefs.respond_to?("#{entry.fetch(:toggle)}?"),
             "toggle #{entry[:toggle]} is not a NotificationPreference column"
    end
  end

  test "dashboard_for: only the member's undismissed rows in that account, newest first" do
    older = record!
    older.update_column(:created_at, 2.days.ago)
    newer     = record!(kind: "budget_warn", period_key: Date.new(2026, 7, 1))
    dismissed = record!(kind: "surplus_nudge", period_key: Date.new(2026, 7, 1))
    dismissed.dismiss!
    other_member = record!(user: users(:english), account: accounts(:english))

    surfaced = Notification.dashboard_for(@user, @account)

    assert_equal [ newer.id, older.id ], surfaced.map(&:id)
    assert_not_includes surfaced.map(&:id), dismissed.id
    assert_not_includes surfaced.map(&:id), other_member.id
  end
end
