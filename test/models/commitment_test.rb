require "test_helper"

class CommitmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(account: @user.account, institution: @inst)
    @card    = CreditCard.create!(account: @user.account, institution: @inst, bill_due_day: 10, closing_offset_days: 7)
  end

  test "requires exactly one instrument (model mirror of the DB check)" do
    assert_not Commitment.new(account: @user.account, name: "x", kind: "fixed", amount_cents: 1,
                              schedule_day: 5, starts_on: Date.current).valid?
    both = Commitment.new(account: @user.account, bank_account: @account, credit_card: @card, name: "x",
                          kind: "fixed", amount_cents: 1, schedule_day: 5, starts_on: Date.current)
    assert_not both.valid?
  end

  test "the DB check rejects two instruments" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Commitment.new(account: @user.account, bank_account: @account, credit_card: @card, name: "x",
                     kind: "fixed", amount_cents: 1, schedule_day: 5, starts_on: Date.current)
        .save!(validate: false)
    end
  end

  test "installment kind requires a count; other kinds forbid it" do
    assert_not Commitment.new(account: @user.account, credit_card: @card, name: "x", kind: "installment",
                              amount_cents: 1, starts_on: Date.current).valid?
    assert_not Commitment.new(account: @user.account, bank_account: @account, name: "x", kind: "fixed",
                              amount_cents: 1, schedule_day: 5, installments_count: 3,
                              starts_on: Date.current).valid?
  end

  test "the DB check pairs kind='installment' with installments_count" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Commitment.new(account: @user.account, credit_card: @card, name: "x", kind: "installment",
                     amount_cents: 1, starts_on: Date.current).save!(validate: false)
    end
  end

  test "occurrence status: overdue past the due date, due_today on it, upcoming before it" do
    month = Date.current.beginning_of_month
    occurrence = ->(day) do
      c = Commitment.create!(account: @user.account, bank_account: @account, name: "conta dia #{day}", kind: "fixed",
                             amount_cents: 10_000, schedule_day: day, starts_on: month)
      CommitmentOccurrence.new(c, month)
    end
    today = Date.current
    assert_equal :due_today, occurrence.call(today.day).status
    assert_equal :overdue,   occurrence.call(today.day - 1).status if today.day > 1
    assert_equal :upcoming,  occurrence.call(today.day + 1).status if today.day < 28
  end

  test "active_in?, last_month, installment_no for an installment plan" do
    c = Commitment.create!(account: @user.account, credit_card: @card, name: "celular", kind: "installment",
                           amount_cents: 50_000, installments_count: 10, starts_on: Date.new(2026, 8, 1))
    assert_equal Date.new(2027, 5, 1), c.last_month              # Aug 2026 + 9 months
    assert c.active_in?(Date.new(2026, 8, 1))
    assert c.active_in?(Date.new(2027, 5, 1))
    assert_not c.active_in?(Date.new(2027, 6, 1))
    assert_not c.active_in?(Date.new(2026, 7, 1))
    assert_equal 14, c.installment_no(Date.new(2027, 9, 1))     # 13 months after Aug 2026
  end

  test "subscription allows a nil schedule_day; due_on defaults to end of month" do
    c = Commitment.create!(account: @user.account, credit_card: @card, name: "Netflix", kind: "subscription",
                           amount_cents: 5_590, starts_on: Date.new(2026, 7, 1))
    assert c.valid?
    assert_equal Date.new(2026, 7, 31), c.due_on(Date.new(2026, 7, 1))
    assert_nil c.last_month
    assert c.active_in?(Date.new(2030, 1, 1))                   # open-ended
  end

  test "paid_in? reflects a posted payment in the month" do
    c = Commitment.create!(account: @user.account, bank_account: @account, name: "aluguel", kind: "fixed",
                           amount_cents: 100_000, schedule_day: 5, starts_on: Date.new(2026, 7, 1))
    assert_not c.paid_in?(Date.new(2026, 7, 1))
    Transaction.create!(account: @user.account, bank_account: @account, commitment: c, status: "posted",
                        amount_cents: 100_000, occurred_on: Date.new(2026, 7, 5))
    assert c.paid_in?(Date.new(2026, 7, 1))
  end

  test "next_charge_month skips already-paid months and ends with the plan" do
    month = Date.current.beginning_of_month
    c = Commitment.create!(account: @user.account, bank_account: @account, name: "carro", kind: "installment",
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
    c = Commitment.create!(account: @user.account, bank_account: @account, name: "curso", kind: "fixed",
                           amount_cents: 50_000, schedule_day: 5, starts_on: start)
    assert_equal start, c.next_charge_month
  end

  # ── Standalone savings (round 3 P4): goal-less "Guardar" needs a savings-account destination ──

  def savings(**attrs)
    Commitment.new({ account: @user.account, bank_account: @account, name: "Guardar", kind: "savings",
                     amount_cents: 10_000, starts_on: Date.current.beginning_of_month }.merge(attrs))
  end

  test "goal-less savings is valid with a savings-kind destination and invalid without one" do
    savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    assert savings(transfer_to_bank_account: savings_account).valid?
    missing = savings
    assert_not missing.valid?
    assert_includes missing.errors.attribute_names, :transfer_to_bank_account
  end

  test "the destination must be a savings account of THIS account, distinct from the source" do
    checking2 = BankAccount.create!(account: @user.account, institution: @inst)
    assert_not savings(transfer_to_bank_account: checking2).valid?          # not savings kind → sobra would jump

    stray = Account.create!(name: "Other").bank_accounts.create!(institution: @inst, kind: "savings")
    assert_not savings(transfer_to_bank_account: stray).valid?              # cross-account

    savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    same = savings(bank_account: savings_account, transfer_to_bank_account: savings_account)
    assert_not same.valid?                                                  # destination == source
    assert_includes same.errors.details[:transfer_to_bank_account].map { |d| d[:error] }, :same_account
  end

  test "a savings commitment can't ride a credit card" do
    savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    bad = savings(bank_account: nil, credit_card: @card, transfer_to_bank_account: savings_account)
    assert_not bad.valid?
    assert_includes bad.errors.details[:credit_card].map { |d| d[:error] }, :not_on_savings
  end

  test "a goal-backed savings commitment stays valid with a nil destination (it lives on the goal)" do
    savings_account = BankAccount.create!(account: @user.account, institution: @inst, kind: "savings")
    goal = @user.account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                                       target_date: Date.new(2027, 12, 1), status: "active",
                                       bank_account: savings_account)
    assert savings(goal:).valid?
  end

  test "destroy detaches paid parcels whole — commitment_id AND installment_number clear together" do
    plan = Commitment.create!(account: @user.account, bank_account: @account, name: "carro", kind: "installment",
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
