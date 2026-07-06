require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  test "per-user name uniqueness is case-insensitive (citext)" do
    @user.account.categories.create!(name: "Mercado")
    assert_not @user.account.categories.new(name: "mercado").valid?
  end

  test "the same name is allowed for different users" do
    @user.account.categories.create!(name: "Mercado")
    assert users(:english).account.categories.create(name: "Mercado").persisted?
  end

  test "deleting a category nullifies its transactions, never destroys them" do
    cat  = @user.account.categories.create!(name: "Mercado")
    acct = BankAccount.create!(account: @user.account, institution: Institution.find_by(code: "260"))
    txn  = Transaction.create!(account: @user.account, bank_account: acct, category: cat, status: "posted",
                               amount_cents: 100, occurred_on: Date.current)
    cat.destroy
    assert_nil txn.reload.category_id
    assert Transaction.exists?(txn.id)
  end
end
