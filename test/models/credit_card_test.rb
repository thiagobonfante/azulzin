require "test_helper"

class CreditCardTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "341")
  end

  test "available credit is limit minus bill; usage ratio reflects it" do
    card = CreditCard.new(user: @user, institution: @inst, credit_limit_reais: "1000", current_bill_reais: "250")
    assert_equal 75000, card.available_cents
    assert_in_delta 0.25, card.usage_ratio, 0.001
  end

  test "an unknown bill counts as zero used" do
    card = CreditCard.new(user: @user, institution: @inst, credit_limit_reais: "1000")
    assert_equal 100000, card.available_cents
    assert_equal 0.0, card.usage_ratio
  end

  test "available and usage are nil when the limit is unknown" do
    card = CreditCard.new(user: @user, institution: @inst)
    assert_not card.limit_informed?
    assert_nil card.available_cents
    assert_nil card.usage_ratio
  end

  test "usage ratio clamps to 1 when the bill exceeds the limit" do
    card = CreditCard.new(user: @user, institution: @inst, credit_limit_reais: "100", current_bill_reais: "500")
    assert_equal 1.0, card.usage_ratio
  end

  test "negative amounts are rejected" do
    card = CreditCard.new(user: @user, institution: @inst, credit_limit_reais: "-5")
    assert_not card.valid?
  end

  test "a zero limit counts as not informed (no nil usage_ratio for the view to crash on)" do
    card = CreditCard.new(user: @user, institution: @inst, credit_limit_reais: "0")
    assert_equal 0, card.credit_limit_cents
    assert_not card.limit_informed?
    assert_nil card.usage_ratio
    assert_nil card.available_cents
  end
end
