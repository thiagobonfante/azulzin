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

  # ── Savings destination (round 3 P4): goal's savings_account wins; standalone falls back to its own ──

  test "a GOAL-LESS savings commitment pays as a two-leg transfer into its own savings account, category nil" do
    savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    category = @user.account.categories.create!(name: "Lazer")
    sav = Commitment.create!(account: @user.account, bank_account: @account, name: "Guardar", kind: "savings",
                             amount_cents: 50_000, starts_on: Date.new(2026, 1, 1),
                             transfer_to_bank_account: savings_account, category: category)
    txn = Commitments::MarkPaid.call(sav, Date.new(2026, 7, 1))
    assert txn.posted?
    assert_equal "transfer",  txn.direction
    assert_equal @account.id, txn.bank_account_id                     # source leg
    assert_equal savings_account.id, txn.transfer_to_bank_account_id         # destination leg
    assert_nil txn.category_id                                        # transfers carry no category
  end

  test "a goal-backed savings commitment still pays into the GOAL's savings account (goal precedence)" do
    goal_savings_account  = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    other_savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    goal = @user.account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                                       target_date: Date.new(2027, 12, 1), status: "active",
                                       bank_account: goal_savings_account)
    sav = Commitment.create!(account: @user.account, bank_account: @account, name: "Carro", kind: "savings",
                             amount_cents: 50_000, starts_on: Date.new(2026, 1, 1),
                             goal: goal, transfer_to_bank_account: other_savings_account)
    txn = Commitments::MarkPaid.call(sav, Date.new(2026, 7, 1))
    assert_equal goal_savings_account.id, txn.transfer_to_bank_account_id    # goal wins over the column
  end
end
