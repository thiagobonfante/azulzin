require "test_helper"

# The F1 window scan (up-tier 02 §1–2, §7): pure event computation over unpaid commitment
# occurrences, card fatura dates, and unreceived expected incomes. Once-per-due-date
# idempotency lives in period_key = the event's date; the end-to-end dedup is asserted in
# Reminders::NotifyMemberJobTest.
class Reminders::ScanTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  TODAY = Date.new(2026, 7, 7)   # a Tuesday, 12:00 SP in the frozen clock below

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    travel_to Time.utc(2026, 7, 7, 15, 0)
  end

  def scan(from: TODAY, to: TODAY + 1) = Reminders::Scan.call(@account, from: from, to: to)

  def fixed_bill!(day:, name: "Luz", amount_cents: 18_240, starts_on: TODAY.beginning_of_month)
    Commitment.create!(account: @account, bank_account: @bank, name: name, kind: "fixed",
                       amount_cents: amount_cents, schedule_day: day, starts_on: starts_on)
  end

  def card!(due_day: 10, offset: 2)
    CreditCard.create!(account: @account, institution: @inst,
                       bill_due_day: due_day, closing_offset_days: offset)
  end

  test "an unpaid fixed commitment due tomorrow → exactly one bill_due with a full snapshot" do
    bill = fixed_bill!(day: 8)

    events = scan
    assert_equal 1, events.size
    event = events.first
    assert_equal "bill_due", event[:kind]
    assert_equal bill, event[:subject]
    assert_equal Date.new(2026, 7, 8), event[:period_key]
    assert_equal({ name: "Luz", amount_cents: 18_240, due_on: "2026-07-08", days_until: 1 },
                 event[:payload])
  end

  test "a paid occurrence produces nothing" do
    bill = fixed_bill!(day: 8)
    Commitments::MarkPaid.call(bill, TODAY.beginning_of_month)

    assert_empty scan
  end

  test "unpaid within the overdue grace → one bill_overdue keyed on the due date" do
    fixed_bill!(day: 5, name: "Água", amount_cents: 9_900)

    events = scan
    assert_equal [ "bill_overdue" ], events.map { |e| e[:kind] }
    assert_equal Date.new(2026, 7, 5), events.first[:period_key]
    assert_equal 2, events.first[:payload][:days_overdue]
  end

  test "unpaid but past the overdue grace → silence" do
    fixed_bill!(day: 1)   # due 2026-07-01; grace covers 07-04..07-06 only

    assert_empty scan
  end

  test "a 3-day lead window carries the bill with its days-until snapshot" do
    fixed_bill!(day: 10)

    events = scan(to: TODAY + 3)
    assert_equal [ "bill_due" ], events.map { |e| e[:kind] }
    assert_equal 3, events.first[:payload][:days_until]
  end

  test "the window spans a month boundary" do
    travel_to Time.utc(2026, 7, 31, 15, 0)
    fixed_bill!(day: 1)   # July occurrence long past grace; August's is due tomorrow

    events = Reminders::Scan.call(@account, from: Date.new(2026, 7, 31), to: Date.new(2026, 8, 1))
    assert_equal [ Date.new(2026, 8, 1) ], events.map { |e| e[:period_key] }
    assert_equal [ "bill_due" ], events.map { |e| e[:kind] }
  end

  test "card fatura: closing and due fire as separate kinds at their own dates" do
    card = card!(due_day: 10, offset: 2)   # July fatura closes 07-08, due 07-10
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 12_300,
                                  occurred_on: Date.new(2026, 7, 1), credit_card: card)

    closing_events = scan   # window 07-07..07-08 catches the closing only
    assert_equal [ "card_closing" ], closing_events.map { |e| e[:kind] }
    closing = closing_events.first
    assert_equal card, closing[:subject]
    assert_equal Date.new(2026, 7, 8), closing[:period_key]
    assert_equal 12_300, closing[:payload][:amount_cents]
    assert_equal 1, closing[:payload][:days_until]

    due_events = scan(from: TODAY + 2, to: TODAY + 3)   # window 07-09..07-10 catches the due
    assert_equal [ "card_due" ], due_events.map { |e| e[:kind] }
    assert_equal Date.new(2026, 7, 10), due_events.first[:period_key]
    assert_equal 12_300, due_events.first[:payload][:amount_cents]
  end

  test "a card without billing config produces nothing and does not crash" do
    CreditCard.create!(account: @account, institution: @inst)   # bill_due_day nil

    assert_empty scan
  end

  test "a card-charged commitment reminds via its occurrence; the fatura is the aggregate" do
    card = card!(due_day: 10, offset: 2)
    Commitment.create!(account: @account, credit_card: card, name: "Streaming", kind: "subscription",
                       amount_cents: 3_990, schedule_day: 8, starts_on: TODAY.beginning_of_month)

    events = scan   # occurrence due 07-08 AND fatura closing 07-08 — different subjects
    assert_equal({ "bill_due" => 1, "card_closing" => 1 }, events.map { |e| e[:kind] }.tally)
    fatura = events.find { |e| e[:kind] == "card_closing" }
    assert_equal 3_990, fatura[:payload][:amount_cents],
                 "the fatura event carries the aggregate (the unlinked charge), never a per-charge reminder"
  end

  test "an expected income in the window and not received → one income_expected" do
    income = Income.create!(account: @account, bank_account: @bank, name: "Salário",
                            amount_cents: 500_000, schedule_kind: "fixed_day", schedule_day: 8)

    events = scan
    assert_equal 1, events.size
    event = events.first
    assert_equal "income_expected", event[:kind]
    assert_equal income, event[:subject]
    assert_equal Date.new(2026, 7, 8), event[:period_key]
    assert_equal({ name: "Salário", amount_cents: 500_000, expected_on: "2026-07-08", days_until: 1 },
                 event[:payload])
  end

  test "an unlinked deposit within ±10% suppresses the income reminder (income_received?)" do
    Income.create!(account: @account, bank_account: @bank, name: "Salário",
                   amount_cents: 500_000, schedule_kind: "fixed_day", schedule_day: 8)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 460_000,
                                  occurred_on: TODAY, bank_account: @bank)   # unlinked, within 10%

    assert_empty scan
  end
end
