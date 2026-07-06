require "test_helper"

# Soft-delete behavior (spine D8): concern mechanics, the unique-index law, the restrict mirror,
# and the money-aggregate impact (a deleted row drops from totals; a deleted instrument does not
# un-spend its rows). Exercised through Category / Transaction / BankAccount on a fixture account.
class SoftDeletableTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
  end

  test "soft_delete! stamps deleted_at/deleted_by and leaves .kept; restore! reverses it" do
    cat = @account.categories.create!(name: "Mercado")
    assert cat.soft_delete!(by: @user)
    assert cat.soft_deleted?
    assert_equal @user, cat.deleted_by
    assert_not @account.categories.kept.exists?(cat.id)
    assert @account.categories.soft_deleted.exists?(cat.id)

    assert cat.restore!(by: @user)
    assert_not cat.reload.soft_deleted?
    assert_nil cat.deleted_by_id
    assert @account.categories.kept.exists?(cat.id)
  end

  test "a duplicate category name is allowed once the first is soft-deleted" do
    a = @account.categories.create!(name: "Mercado")
    assert_not @account.categories.new(name: "mercado").valid?      # citext dup blocked while kept
    a.soft_delete!(by: @user)
    assert @account.categories.create!(name: "Mercado").persisted?  # dead row does not block
  end

  test "a second commitment-month payment is allowed after soft-deleting the first" do
    acct = @account.bank_accounts.create!(institution: @inst)
    com  = @account.commitments.create!(bank_account: acct, name: "aluguel", kind: "fixed",
             amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    first = Commitments::MarkPaid.call(com, Date.current.beginning_of_month)
    first.soft_delete!(by: @user)
    second = Commitments::MarkPaid.call(com, Date.current.beginning_of_month)   # index frees the slot
    assert second.persisted?
    assert_not_equal first.id, second.id
  end

  test "a WhatsApp replay never resurrects a soft-deleted transaction (source_message_id keeps the slot)" do
    txn = @account.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "posted",
            direction: "expense", source_message_id: "wamid-123", created_by: @user)
    txn.soft_delete!(by: @user)
    replay = Transaction.find_or_create_by!(source_message_id: "wamid-123") do |t|
      t.account = @account; t.amount_cents = 999; t.occurred_on = Date.current
    end
    assert_equal txn.id, replay.id
    assert replay.soft_deleted?, "still dead — a redelivered webhook must not un-delete it"
    assert_equal 1, @account.transactions.where(source_message_id: "wamid-123").count
  end

  test "BankAccount#soft_delete! refuses while a kept income depends on it" do
    acct = @account.bank_accounts.create!(institution: @inst)
    @account.incomes.create!(bank_account: acct, name: "salário", amount_cents: 100,
      schedule_kind: "fixed_day", schedule_day: 5)
    assert_not acct.soft_delete!(by: @user)
    assert acct.errors.added?(:base, :has_kept_incomes)
    assert_not acct.reload.soft_deleted?
  end

  test "a soft-deleted transaction drops from MonthSummary; a soft-deleted instrument does not un-spend its kept rows" do
    month = Date.current.beginning_of_month
    acct = @account.bank_accounts.create!(institution: @inst, balance_cents: 0)
    @account.transactions.create!(amount_cents: 3_000, occurred_on: Date.current, status: "posted", direction: "expense", bank_account: acct)
    drop = @account.transactions.create!(amount_cents: 5_000, occurred_on: Date.current, status: "posted", direction: "expense", bank_account: acct)

    drop.soft_delete!(by: @user)
    assert_equal 3_000, MonthSummary.new(@account, month).saidas_cents   # the deleted row drops out

    acct.soft_delete!(by: @user)                                          # no cascade to its transactions
    assert_equal 3_000, MonthSummary.new(@account, month).saidas_cents   # the kept row still counts
  end
end
