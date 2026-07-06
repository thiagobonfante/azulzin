require "test_helper"

class BankAccountTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
  end

  test "requires an institution" do
    account = BankAccount.new(user: @user)
    assert_not account.valid?
    assert account.errors.key?(:institution)
  end

  test "balance_reais parses into cents and formats back" do
    account = BankAccount.new(user: @user, institution: @inst, balance_reais: "1.500,00")
    assert_equal 150000, account.balance_cents
    assert account.balance_informed?
    assert_equal "1500,00", account.balance_reais
  end

  test "balance stays unset when blank" do
    account = BankAccount.new(user: @user, institution: @inst, balance_reais: "")
    assert_nil account.balance_cents
    assert_not account.balance_informed?
  end

  test "display_name uses the nickname, falling back to the institution" do
    account = BankAccount.new(user: @user, institution: @inst)
    assert_equal "Nubank", account.display_name
    account.nickname = "Salário"
    assert_equal "Salário", account.display_name
  end

  test "derived balance adds signed posted rows created after the anchor" do
    account = BankAccount.create!(user: @user, institution: @inst, balance_cents: 100_000)
    other   = BankAccount.create!(user: @user, institution: @inst, balance_cents: 0)
    post = ->(attrs) { @user.transactions.create!({ status: "posted", occurred_on: Date.current }.merge(attrs)) }
    post.call(direction: "expense",  bank_account: account, amount_cents: 3_000)
    post.call(direction: "income",   bank_account: account, amount_cents: 5_000)
    post.call(direction: "transfer", bank_account: account, transfer_to_bank_account: other, amount_cents: 2_000)
    post.call(direction: "transfer", bank_account: other, transfer_to_bank_account: account, amount_cents: 1_500)
    assert_equal 100_000 - 3_000 + 5_000 - 2_000 + 1_500, account.derived_balance_cents
    assert_equal 0 + 2_000 - 1_500, other.derived_balance_cents
  end

  test "derived balance is nil when the balance was never informed" do
    account = BankAccount.create!(user: @user, institution: @inst)
    assert_nil account.derived_balance_cents
  end

  test "re-anchoring the balance absorbs rows recorded before the edit" do
    account = BankAccount.create!(user: @user, institution: @inst, balance_cents: 100_000)
    @user.transactions.create!(status: "posted", occurred_on: Date.current, direction: "expense",
                               bank_account: account, amount_cents: 3_000)
    account.update!(balance_cents: 90_000) # stamps a fresh anchor — the expense is now inside it
    assert_equal 90_000, account.derived_balance_cents
  end
end
