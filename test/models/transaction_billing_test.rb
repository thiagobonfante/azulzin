require "test_helper"

# billing_month computation, sticky manual moves, the new check constraints, and the
# paid-once partial index (with its card-parcel exemption). Phase 0 VERIFY targets.
class TransactionBillingTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @account = BankAccount.create!(user: @user, institution: @inst)
    @card    = CreditCard.create!(user: @user, institution: @inst, bill_due_day: 10, closing_offset_days: 7)
  end

  # billing_month is provided so validate:false saves don't trip NOT NULL before the check
  # constraint we're actually testing; normal saves recompute it via before_validation anyway.
  def build(**attrs)
    Transaction.new({ user: @user, amount_cents: 1_000, occurred_on: Date.new(2026, 7, 4),
                      billing_month: Date.new(2026, 7, 1), status: "posted" }.merge(attrs))
  end

  test "bank and unassigned rows bucket by calendar month" do
    t = build(bank_account: @account); t.save!
    assert_equal Date.new(2026, 7, 1), t.billing_month
    u = build; u.save!
    assert_equal Date.new(2026, 7, 1), u.billing_month
  end

  test "card rows bucket by the closing rule (d10/f7, 07-04 → August)" do
    t = build(credit_card: @card); t.save!
    assert_equal Date.new(2026, 8, 1), t.billing_month
  end

  test "card parcels stagger billing_month by installment_number" do
    plan = Commitment.create!(user: @user, credit_card: @card, name: "celular", kind: "installment",
                              amount_cents: 50_000, installments_count: 3, starts_on: Date.new(2026, 8, 1))
    (1..3).each do |k|
      p = build(credit_card: @card, commitment: plan, installment_number: k); p.save!
      assert_equal(Date.new(2026, 8, 1) >> (k - 1), p.billing_month, "parcel #{k}")
    end
  end

  test "a manual move is sticky across occurred_on edits (invariant §9.5)" do
    t = build(credit_card: @card); t.save!
    t.update!(billing_month: Date.new(2026, 9, 1), billing_month_manual: true)
    t.update!(occurred_on: Date.new(2026, 6, 1))
    assert_equal Date.new(2026, 9, 1), t.reload.billing_month
    assert t.billing_month_manual?
  end

  test "assign_instrument! resets the manual flag and recomputes billing_month" do
    t = build(credit_card: @card); t.save!
    t.update!(billing_month: Date.new(2026, 12, 1), billing_month_manual: true)
    t.assign_instrument!(@account)
    assert_not t.reload.billing_month_manual?
    assert_equal Date.new(2026, 7, 1), t.billing_month
  end

  test "check: transfer_to_bank_account_id only on a transfer row" do
    assert_raises(ActiveRecord::StatementInvalid) do
      build(bank_account: @account, transfer_to_bank_account_id: @account.id, direction: "expense")
        .save!(validate: false)
    end
  end

  test "check: installment_number requires a commitment" do
    assert_raises(ActiveRecord::StatementInvalid) do
      build(credit_card: @card, installment_number: 1).save!(validate: false)
    end
  end

  test "paid-once: a second posted debit payment for one (commitment, month) raises RecordNotUnique" do
    c = fixed_commitment
    build(bank_account: @account, commitment: c, occurred_on: Date.new(2026, 7, 5)).save!
    assert_raises(ActiveRecord::RecordNotUnique) do
      build(bank_account: @account, commitment: c, occurred_on: Date.new(2026, 7, 6)).save!(validate: false)
    end
  end

  test "paid-once: reverse! (→ rejected) frees the slot; a new posted payment succeeds" do
    c = fixed_commitment
    first = build(bank_account: @account, commitment: c, occurred_on: Date.new(2026, 7, 5)); first.save!
    first.reverse!
    assert_nothing_raised do
      build(bank_account: @account, commitment: c, occurred_on: Date.new(2026, 7, 5)).save!
    end
  end

  test "paid-once EXEMPTS card parcels sharing a fatura (R2 manual move)" do
    plan = Commitment.create!(user: @user, credit_card: @card, name: "tv", kind: "installment",
                              amount_cents: 20_000, installments_count: 2, starts_on: Date.new(2026, 8, 1))
    p1 = build(credit_card: @card, commitment: plan, installment_number: 1); p1.save!
    p2 = build(credit_card: @card, commitment: plan, installment_number: 2); p2.save!
    assert_nothing_raised do
      p2.update!(billing_month: p1.billing_month, billing_month_manual: true)
    end
    assert_equal p1.billing_month, p2.reload.billing_month
  end

  private
    def fixed_commitment
      Commitment.create!(user: @user, bank_account: @account, name: "aluguel", kind: "fixed",
                         amount_cents: 100_000, schedule_day: 5, starts_on: Date.new(2026, 7, 1))
    end
end
