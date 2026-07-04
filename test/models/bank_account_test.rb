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
end
