require "test_helper"

class Commitments::MarkPaidTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(account: @user.account, institution: @inst)
    @commitment = Commitment.create!(account: @user.account, bank_account: @account, name: "aluguel", kind: "fixed",
                                     amount_cents: 100_000, schedule_day: 5, starts_on: Date.new(2026, 1, 1))
  end

  test "a past-month payment sets billing_month manually (never re-bucketed)" do
    txn = Commitments::MarkPaid.call(@commitment, Date.new(2026, 5, 1))
    assert txn.posted?
    assert_equal Date.new(2026, 5, 1), txn.billing_month
    assert txn.billing_month_manual?
    assert_equal @account, txn.bank_account
    assert @commitment.paid_in?(Date.new(2026, 5, 1))
  end

  test "double-pay is a friendly no-op — no second row" do
    Commitments::MarkPaid.call(@commitment, Date.new(2026, 7, 1))
    assert_no_difference -> { @commitment.payments.posted.count } do
      assert Commitments::MarkPaid.call(@commitment, Date.new(2026, 7, 1)).present?
    end
  end

  test "unpay (reverse!) frees the slot; re-pay succeeds" do
    first = Commitments::MarkPaid.call(@commitment, Date.new(2026, 7, 1))
    first.reverse!
    assert_not @commitment.paid_in?(Date.new(2026, 7, 1))
    assert_nothing_raised { Commitments::MarkPaid.call(@commitment, Date.new(2026, 7, 1)) }
    assert @commitment.paid_in?(Date.new(2026, 7, 1))
  end

  test "the amount is overridable" do
    txn = Commitments::MarkPaid.call(@commitment, Date.new(2026, 7, 1), amount: 101_000)
    assert_equal 101_000, txn.amount_cents
  end
end
