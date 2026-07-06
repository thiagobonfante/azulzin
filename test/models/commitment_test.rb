require "test_helper"

class CommitmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(user: @user, institution: @inst)
    @card    = CreditCard.create!(user: @user, institution: @inst, bill_due_day: 10, closing_offset_days: 7)
  end

  test "requires exactly one instrument (model mirror of the DB check)" do
    assert_not Commitment.new(user: @user, name: "x", kind: "fixed", amount_cents: 1,
                              schedule_day: 5, starts_on: Date.current).valid?
    both = Commitment.new(user: @user, bank_account: @account, credit_card: @card, name: "x",
                          kind: "fixed", amount_cents: 1, schedule_day: 5, starts_on: Date.current)
    assert_not both.valid?
  end

  test "the DB check rejects two instruments" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Commitment.new(user: @user, bank_account: @account, credit_card: @card, name: "x",
                     kind: "fixed", amount_cents: 1, schedule_day: 5, starts_on: Date.current)
        .save!(validate: false)
    end
  end

  test "installment kind requires a count; other kinds forbid it" do
    assert_not Commitment.new(user: @user, credit_card: @card, name: "x", kind: "installment",
                              amount_cents: 1, starts_on: Date.current).valid?
    assert_not Commitment.new(user: @user, bank_account: @account, name: "x", kind: "fixed",
                              amount_cents: 1, schedule_day: 5, installments_count: 3,
                              starts_on: Date.current).valid?
  end

  test "the DB check pairs kind='installment' with installments_count" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Commitment.new(user: @user, credit_card: @card, name: "x", kind: "installment",
                     amount_cents: 1, starts_on: Date.current).save!(validate: false)
    end
  end

  test "occurrence status: overdue past the due date, due_today on it, upcoming before it" do
    month = Date.current.beginning_of_month
    occurrence = ->(day) do
      c = Commitment.create!(user: @user, bank_account: @account, name: "conta dia #{day}", kind: "fixed",
                             amount_cents: 10_000, schedule_day: day, starts_on: month)
      CommitmentOccurrence.new(c, month)
    end
    today = Date.current
    assert_equal :due_today, occurrence.call(today.day).status
    assert_equal :overdue,   occurrence.call(today.day - 1).status if today.day > 1
    assert_equal :upcoming,  occurrence.call(today.day + 1).status if today.day < 28
  end

  test "active_in?, last_month, installment_no for an installment plan" do
    c = Commitment.create!(user: @user, credit_card: @card, name: "celular", kind: "installment",
                           amount_cents: 50_000, installments_count: 10, starts_on: Date.new(2026, 8, 1))
    assert_equal Date.new(2027, 5, 1), c.last_month              # Aug 2026 + 9 months
    assert c.active_in?(Date.new(2026, 8, 1))
    assert c.active_in?(Date.new(2027, 5, 1))
    assert_not c.active_in?(Date.new(2027, 6, 1))
    assert_not c.active_in?(Date.new(2026, 7, 1))
    assert_equal 14, c.installment_no(Date.new(2027, 9, 1))     # 13 months after Aug 2026
  end

  test "subscription allows a nil schedule_day; due_on defaults to end of month" do
    c = Commitment.create!(user: @user, credit_card: @card, name: "Netflix", kind: "subscription",
                           amount_cents: 5_590, starts_on: Date.new(2026, 7, 1))
    assert c.valid?
    assert_equal Date.new(2026, 7, 31), c.due_on(Date.new(2026, 7, 1))
    assert_nil c.last_month
    assert c.active_in?(Date.new(2030, 1, 1))                   # open-ended
  end

  test "paid_in? reflects a posted payment in the month" do
    c = Commitment.create!(user: @user, bank_account: @account, name: "aluguel", kind: "fixed",
                           amount_cents: 100_000, schedule_day: 5, starts_on: Date.new(2026, 7, 1))
    assert_not c.paid_in?(Date.new(2026, 7, 1))
    Transaction.create!(user: @user, bank_account: @account, commitment: c, status: "posted",
                        amount_cents: 100_000, occurred_on: Date.new(2026, 7, 5))
    assert c.paid_in?(Date.new(2026, 7, 1))
  end

  test "next_charge_month skips already-paid months and ends with the plan" do
    month = Date.current.beginning_of_month
    c = Commitment.create!(user: @user, bank_account: @account, name: "carro", kind: "installment",
                           amount_cents: 120_000, installments_count: 3, schedule_day: 10, starts_on: month)
    assert_equal month, c.next_charge_month
    Commitments::MarkPaid.call(c, month)
    assert_equal month >> 1, c.next_charge_month
    Commitments::MarkPaid.call(c, month >> 1)
    Commitments::MarkPaid.call(c, month >> 2)
    assert_nil c.next_charge_month
  end

  test "next_charge_month of a future-starting commitment is its first month" do
    start = Date.current.beginning_of_month >> 2
    c = Commitment.create!(user: @user, bank_account: @account, name: "curso", kind: "fixed",
                           amount_cents: 50_000, schedule_day: 5, starts_on: start)
    assert_equal start, c.next_charge_month
  end

  test "destroy detaches paid parcels whole — commitment_id AND installment_number clear together" do
    plan = Commitment.create!(user: @user, bank_account: @account, name: "carro", kind: "installment",
                              amount_cents: 100_000, installments_count: 12,
                              starts_on: Date.current.beginning_of_month)
    parcel = Commitments::MarkPaid.call(plan, Date.current.beginning_of_month)
    assert_equal 1, parcel.installment_number

    assert_nothing_raised { plan.destroy! }

    parcel.reload
    assert_nil parcel.commitment_id
    assert_nil parcel.installment_number   # paired by the transactions_installment_requires_commitment check
    assert parcel.posted?                  # history survives the plan's deletion
  end
end
