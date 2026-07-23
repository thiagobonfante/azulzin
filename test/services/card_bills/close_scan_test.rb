require "test_helper"

# The close scan's mechanics (.plans/credit-cards 01 §2): idempotent by the unique index,
# zero-bill skip (P0 #1), catch-up between rows, open month untouched, snapshots frozen.
class CardBills::CloseScanTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    # due day 10, closes the 3rd; frozen at Jul 7 ⇒ July's bill closed on Jul 3, August open.
    @card = CreditCard.create!(account: @account, institution: @inst,
                               bill_due_day: 10, closing_offset_days: 7)
    travel_to Time.utc(2026, 7, 7, 15, 0)
  end

  JULY = Date.new(2026, 7, 1)

  def spend!(cents, on:)
    @account.transactions.create!(direction: "expense", status: "posted", credit_card: @card,
                                  amount_cents: cents, occurred_on: on, merchant: "Loja")
  end

  test "zero bill: no row, month renders as an empty computed fatura (P0 #1)" do
    assert_empty CardBills::CloseScan.ensure_for(@card)
    assert_equal 0, CardBill.count
  end

  test "closes the most recent month with frozen snapshots, idempotently" do
    spend!(12_345, on: Date.new(2026, 7, 1))

    2.times { CardBills::CloseScan.ensure_for(@card) }

    bill = CardBill.sole
    assert_equal JULY, bill.billing_month
    assert_equal Date.new(2026, 7, 3),  bill.closed_on
    assert_equal Date.new(2026, 7, 10), bill.due_on
    assert_equal 12_345, bill.computed_total_cents
  end

  test "catch-up: fills the gap after the last existing row, skips zero months, leaves the open month" do
    spend!(10_000, on: Date.new(2026, 5, 1))   # May bill
    spend!(20_000, on: Date.new(2026, 7, 1))   # July bill; June stays zero
    CardBills::CloseScan.close(@card, Date.new(2026, 5, 1))

    CardBills::CloseScan.ensure_for(@card)

    assert_equal [ Date.new(2026, 5, 1), JULY ], CardBill.order(:billing_month).pluck(:billing_month)
    assert_nil CardBill.find_by(billing_month: Date.new(2026, 8, 1)), "open month untouched"
  end

  test "a later config edit never rewrites the settled snapshots" do
    spend!(12_345, on: Date.new(2026, 7, 1))
    CardBills::CloseScan.ensure_for(@card)

    @card.update!(bill_due_day: 20)
    CardBills::CloseScan.ensure_for(@card)

    assert_equal Date.new(2026, 7, 10), CardBill.find_by!(billing_month: JULY).due_on
  end

  test "unconfigured card: no-op" do
    unconfigured = CreditCard.create!(account: @account, institution: @inst)
    assert_empty CardBills::CloseScan.ensure_for(unconfigured)
  end
end
