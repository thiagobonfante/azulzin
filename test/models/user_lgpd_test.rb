require "test_helper"

# LGPD parity: destroying a user erases every record they own, in an order that respects the
# NO-ACTION FKs (commitments/incomes point at accounts; incomes restrict their account).
class UserLgpdTest < ActiveSupport::TestCase
  test "user.destroy removes incomes, categories, commitments, and their transactions" do
    user = User.create!(email_address: "lgpd@example.com", password: "password123")
    inst = Institution.find_by(code: "260")
    acct = user.bank_accounts.create!(institution: inst)
    cat  = user.categories.create!(name: "Mercado")
    user.incomes.create!(bank_account: acct, name: "salário", amount_cents: 450_000, schedule_kind: "fixed_day", schedule_day: 5)
    com  = user.commitments.create!(bank_account: acct, category: cat, name: "aluguel", kind: "fixed",
                                    amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    Commitments::MarkPaid.call(com, Date.current.beginning_of_month)
    user.transactions.create!(bank_account: acct, direction: "expense", status: "posted", amount_cents: 100, occurred_on: Date.current)

    assert_nothing_raised { user.destroy }

    assert_equal 0, Income.where(user_id: user.id).count
    assert_equal 0, Category.where(user_id: user.id).count
    assert_equal 0, Commitment.where(user_id: user.id).count
    assert_equal 0, Transaction.where(user_id: user.id).count
    assert_equal 0, BankAccount.where(user_id: user.id).count
  end

  test "deleting a category nullifies a commitment's category, never breaks it" do
    user = users(:confirmed)
    inst = Institution.find_by(code: "260")
    acct = user.bank_accounts.create!(institution: inst)
    cat  = user.categories.create!(name: "Contas")
    com  = user.commitments.create!(bank_account: acct, category: cat, name: "luz", kind: "fixed",
                                    amount_cents: 10_000, schedule_day: 5, starts_on: Date.current)
    cat.destroy
    assert_nil com.reload.category_id
    assert Commitment.exists?(com.id)
  end
end
