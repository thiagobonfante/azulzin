require "test_helper"

# MoneyColumns.prefill is the one cents→prefill-string formatter (pt-BR shape, integer math,
# no floats) — shared by the generated `_reais` accessors and the budget-suggest endpoint.
class MoneyColumnsTest < ActiveSupport::TestCase
  test "prefill formats cents with a comma, two decimals and no grouping" do
    assert_equal "1234,56", MoneyColumns.prefill(123_456)
    assert_equal "420,00",  MoneyColumns.prefill(42_000)
    assert_equal "0,05",    MoneyColumns.prefill(5)
    assert_equal "0,00",    MoneyColumns.prefill(0)
    assert_equal "-0,50",   MoneyColumns.prefill(-50)
    assert_nil MoneyColumns.prefill(nil)
  end

  test "the generated _reais accessor keeps the exact prefill shape" do
    category = Category.new(monthly_budget_cents: 123_456)
    assert_equal "1234,56", category.monthly_budget_reais
    assert_nil Category.new(monthly_budget_cents: nil).monthly_budget_reais
  end
end
