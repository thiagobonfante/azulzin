require "test_helper"

class MoneyTest < ActiveSupport::TestCase
  test "parses pt-BR, en-US and plain formats into cents" do
    assert_equal 123456, Money.to_cents("1.234,56")     # pt-BR
    assert_equal 123456, Money.to_cents("1,234.56")     # en-US
    assert_equal 123400, Money.to_cents("1234")         # integer reais
    assert_equal 123450, Money.to_cents("1234,5")       # one decimal digit
    assert_equal 123400, Money.to_cents("1.234")        # pt-BR thousands, no decimals
    assert_equal 123456, Money.to_cents("R$ 1.234,56")  # currency symbol stripped
    assert_equal 150,    Money.to_cents("1,50")
    assert_equal 0,      Money.to_cents("0,00")
  end

  test "blank or non-numeric input is nil" do
    assert_nil Money.to_cents(nil)
    assert_nil Money.to_cents("")
    assert_nil Money.to_cents("   ")
    assert_nil Money.to_cents("abc")
    assert_nil Money.to_cents("-")
  end

  test "negative amounts are preserved" do
    assert_equal(-500, Money.to_cents("-5"))
    assert_equal(-123456, Money.to_cents("-1.234,56"))
  end
end
