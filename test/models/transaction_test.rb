require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(user: @user, institution: @inst)
    @card    = CreditCard.create!(user: @user, institution: @inst)
  end

  def build(**attrs)
    Transaction.new({ user: @user, amount_cents: 1_323, occurred_on: Date.current }.merge(attrs))
  end

  test "a posted transaction may have ZERO instruments (unassigned, assign in-app)" do
    txn = build(status: "posted")
    assert txn.save, txn.errors.full_messages.to_sentence
    assert_nil txn.instrument
    assert_not txn.assigned?
  end

  test "a transaction may have exactly one instrument" do
    assert build(status: "posted", bank_account: @account).save
    assert build(status: "posted", credit_card: @card).save
  end

  test "the check constraint rejects BOTH instruments at once" do
    assert_raises(ActiveRecord::StatementInvalid) do
      build(status: "posted", bank_account: @account, credit_card: @card).save!(validate: false)
    end
  end

  test "status and direction are string-backed enums" do
    txn = build
    assert_equal "pending_review", txn.status
    assert_equal "expense", txn.direction
    txn.status = "posted"
    assert txn.posted?
  end

  test "open_ask_for returns nil for a fresh user" do
    assert_nil Transaction.open_ask_for(@user)
  end

  test "open_ask_for returns the latest unexpired ask, ignoring expired ones" do
    build(status: "needs_confirmation", ask_expires_at: 1.hour.ago).save!         # expired
    fresh = build(status: "needs_confirmation", ask_expires_at: 30.minutes.from_now)
    fresh.save!
    assert_equal fresh, Transaction.open_ask_for(@user)
  end

  test "spend scope counts only posted expenses" do
    build(status: "posted",         amount_cents: 1_000, bank_account: @account).save!
    build(status: "rejected",       amount_cents: 9_999, bank_account: @account).save!
    build(status: "pending_review", amount_cents: 8_888).save!
    assert_equal 1_000, @user.transactions.spend.sum(:amount_cents)
  end
end
