require "test_helper"

# The one spend map (up-tier 03 §2): posted expenses grouped by category at billing_month
# — card purchases at their fatura's month (D4) — plus unpaid debit commitments folded in.
# The hero bar and Budgets::Check both read this, so the definitions can never drift.
class Budgets::ActualsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  JULY = Date.new(2026, 7, 1)

  setup do
    @account = users(:confirmed).account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    @cat     = @account.categories.create!(name: "Restaurantes")
  end

  test "posted bank expenses count at their billing month" do
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 12_000,
                                  occurred_on: Date.new(2026, 7, 5), category: @cat, bank_account: @bank)

    assert_equal 12_000, Budgets::Actuals.for(@account, JULY)[@cat.id]
  end

  test "a card purchase counts toward the fatura's billing month, not the calendar month" do
    card = CreditCard.create!(account: @account, institution: @inst,
                              bill_due_day: 10, closing_offset_days: 2)   # July fatura closes 07-08
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 9_000,
                                  occurred_on: Date.new(2026, 7, 9), category: @cat, credit_card: card)

    assert_nil Budgets::Actuals.for(@account, JULY)[@cat.id], "after closing → next fatura"
    assert_equal 9_000, Budgets::Actuals.for(@account, Date.new(2026, 8, 1))[@cat.id]
  end

  test "incomes and transfers never count against a category" do
    other = @account.bank_accounts.create!(institution: @inst)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 50_000,
                                  occurred_on: Date.new(2026, 7, 5), category: @cat, bank_account: @bank)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 20_000,
                                  occurred_on: Date.new(2026, 7, 5), bank_account: @bank,
                                  transfer_to_bank_account: other)

    assert_nil Budgets::Actuals.for(@account, JULY)[@cat.id]
  end

  test "an unpaid debit commitment folds in by category; paying it never double-counts" do
    travel_to Time.utc(2026, 7, 7, 15, 0) do
      bill = Commitment.create!(account: @account, bank_account: @bank, name: "Academia",
                                kind: "fixed", amount_cents: 15_000, schedule_day: 20,
                                starts_on: JULY, category: @cat)
      assert_equal 15_000, Budgets::Actuals.for(@account, JULY)[@cat.id], "projected while unpaid"

      Commitments::MarkPaid.call(bill, JULY)
      assert_equal 15_000, Budgets::Actuals.for(@account, JULY)[@cat.id],
                   "paid → the posted payment row counts once, the projection drops out"
    end
  end
end
