require "test_helper"

# LGPD parity under tenancy (spine D8): the hard-destroy cascade moved from User to Account.
# Erasing a household = destroying the Account, in an order that respects the NO-ACTION FKs
# (commitments/incomes point at bank accounts; incomes restrict their account). Erasing a single
# PERSON = destroying the User, which leaves the shared account's rows but nulls their attribution.
class UserLgpdTest < ActiveSupport::TestCase
  test "account.destroy removes incomes, categories, commitments, and their transactions" do
    user    = User.create!(email_address: "lgpd@example.com", password: "password123")
    account = Accounts::Bootstrap.call(user)
    inst = Institution.find_by(code: "260")
    acct = account.bank_accounts.create!(institution: inst)
    cat  = account.categories.create!(name: "Mercado")
    account.incomes.create!(bank_account: acct, name: "salário", amount_cents: 450_000, schedule_kind: "fixed_day", schedule_day: 5)
    com  = account.commitments.create!(bank_account: acct, category: cat, name: "aluguel", kind: "fixed",
                                       amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    Commitments::MarkPaid.call(com, Date.current.beginning_of_month)
    # A PAID PARCEL is the hard case: its transaction carries installment_number, which the DB
    # pairs with commitment_id — the cascade must detach both together, never one without the other.
    plan = account.commitments.create!(bank_account: acct, name: "carro", kind: "installment",
                                       amount_cents: 200_000, installments_count: 12,
                                       starts_on: Date.current.beginning_of_month)
    Commitments::MarkPaid.call(plan, Date.current.beginning_of_month)
    account.transactions.create!(bank_account: acct, direction: "expense", status: "posted", amount_cents: 100, occurred_on: Date.current)

    assert_nothing_raised { account.destroy }

    assert_equal 0, Income.where(account_id: account.id).count
    assert_equal 0, Category.where(account_id: account.id).count
    assert_equal 0, Commitment.where(account_id: account.id).count
    assert_equal 0, Transaction.where(account_id: account.id).count
    assert_equal 0, BankAccount.where(account_id: account.id).count
  end

  test "user.destroy keeps the shared account's rows but nulls their created_by attribution" do
    account = accounts(:confirmed)
    member  = User.create!(email_address: "member@example.com", password: "password123")
    account.memberships.create!(user: member, role: "member")
    acct = account.bank_accounts.create!(institution: Institution.find_by(code: "260"), created_by: member)

    assert_nothing_raised { member.destroy }
    assert BankAccount.exists?(acct.id), "the row belongs to the account, not the user — it survives"
    assert_nil acct.reload.created_by_id, "attribution nulls out (ON DELETE SET NULL)"
  end

  test "deleting a category nullifies a commitment's category, never breaks it" do
    user = users(:confirmed)
    inst = Institution.find_by(code: "260")
    acct = user.account.bank_accounts.create!(institution: inst)
    cat  = user.account.categories.create!(name: "Contas")
    com  = user.account.commitments.create!(bank_account: acct, category: cat, name: "luz", kind: "fixed",
                                            amount_cents: 10_000, schedule_day: 5, starts_on: Date.current)
    cat.destroy
    assert_nil com.reload.category_id
    assert Commitment.exists?(com.id)
  end
end
