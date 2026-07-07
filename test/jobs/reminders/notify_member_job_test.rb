require "test_helper"

# One member's daily sweep, end to end (up-tier 02 §3–4, §7): scan at the member's
# lead-days → Notification.record! (once-per-due-date dedup) → Notifications::Deliver
# (inert this phase: dashboard rows only, no claim burned).
class Reminders::NotifyMemberJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    travel_to Time.utc(2026, 7, 7, 15, 0)   # 12:00 SP → today_sp = 2026-07-07
  end

  def run_for(user = @user) = Reminders::NotifyMemberJob.perform_now(@account.id, user.id)

  def fixed_bill!(day:, name: "Luz")
    Commitment.create!(account: @account, bank_account: @bank, name: name, kind: "fixed",
                       amount_cents: 18_240, schedule_day: day, starts_on: Date.new(2026, 7, 1))
  end

  test "a bill due tomorrow → exactly one row; a same-day re-run stays at one (dedup)" do
    bill = fixed_bill!(day: 8)

    assert_difference(-> { Notification.count }, 1) { run_for }
    assert_no_difference(-> { Notification.count }) { run_for }

    row = Notification.find_by!(kind: "bill_due")
    assert_equal @user, row.user
    assert_equal bill, row.subject
    assert_equal Date.new(2026, 7, 8), row.period_key
    assert_nil row.whatsapp_sent_at, "dashboard-only phase: Deliver must not burn a claim"
  end

  test "paid before the next scan → no new row (not even an overdue nudge)" do
    bill = fixed_bill!(day: 8)
    run_for   # reminds while unpaid
    Commitments::MarkPaid.call(bill, Date.new(2026, 7, 1))

    travel_to Time.utc(2026, 7, 9, 15, 0)   # past the due date, inside the grace window
    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "overdue and still unpaid → the bill_overdue nudge, once" do
    fixed_bill!(day: 5)

    assert_difference(-> { Notification.where(kind: "bill_overdue").count }, 1) { run_for }
    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "lead_days 3 → reminds once at first entry into the window, silent after" do
    @user.notification_prefs.update!(bill_reminder_lead_days: 3)
    fixed_bill!(day: 10)

    assert_difference(-> { Notification.count }, 1) { run_for }
    row = Notification.find_by!(kind: "bill_due")
    assert_equal 3, row.payload["days_until"]

    [ 8, 9, 10 ].each do |day|
      travel_to Time.utc(2026, 7, day, 15, 0)
      assert_no_difference(-> { Notification.count }) { run_for }
    end
  end

  test "card closing and due each land once, at their own dates, with the event discriminator" do
    card = CreditCard.create!(account: @account, institution: @inst,
                              bill_due_day: 10, closing_offset_days: 2)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 12_300,
                                  occurred_on: Date.new(2026, 7, 1), credit_card: card)

    run_for                                   # 07-07: closing (07-08) enters the window
    travel_to Time.utc(2026, 7, 9, 15, 0)
    run_for                                   # 07-09: due (07-10) enters the window
    run_for                                   # re-run: dedup holds

    rows = Notification.where(kind: "card_bill").order(:period_key)
    assert_equal [ Date.new(2026, 7, 8), Date.new(2026, 7, 10) ], rows.map(&:period_key)
    assert_equal %w[closing due], rows.map { |r| r.payload["event"] }
  end

  test "the bill_reminders toggle off → the member's sweep is skipped entirely" do
    @user.notification_prefs.update!(bill_reminders: false)
    fixed_bill!(day: 8)

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "two members opted in → one row each; one toggled off → one row" do
    other = User.create!(email_address: "member@example.com", password: "password123")
    @account.add_member!(other)
    fixed_bill!(day: 8)

    run_for(@user)
    run_for(other)
    assert_equal [ @user.id, other.id ].sort,
                 Notification.where(kind: "bill_due").pluck(:user_id).sort

    other.notification_prefs.update!(bill_reminders: false)
    fixed_bill!(day: 8, name: "Internet")
    run_for(@user)
    run_for(other)
    rows = Notification.where(kind: "bill_due").where("payload->>'name' = ?", "Internet")
    assert_equal [ @user.id ], rows.pluck(:user_id)
  end

  test "a member no longer in the account gets nothing" do
    outsider = users(:english)   # belongs to another account
    fixed_bill!(day: 8)

    assert_no_difference -> { Notification.count } do
      Reminders::NotifyMemberJob.perform_now(@account.id, outsider.id)
    end
  end

  test "no timezone drift: 'tomorrow' is São Paulo's tomorrow, not UTC's" do
    travel_to Time.utc(2026, 7, 8, 1, 30)   # already Jul 8 in UTC, still Jul 7 22:30 in SP
    fixed_bill!(day: 8)

    run_for
    row = Notification.find_by!(kind: "bill_due")
    assert_equal Date.new(2026, 7, 8), row.period_key
    assert_equal 1, row.payload["days_until"], "due on the 8th is 'amanhã' in SP, not 'hoje'"
  end
end
