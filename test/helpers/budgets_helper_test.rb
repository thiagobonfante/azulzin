require "test_helper"

class BudgetsHelperTest < ActionView::TestCase
  # The 03 §8 bar-color targets at the default 80/100 bands.
  test "budget bar: primary under warn, warning at 85%, error at 105%" do
    assert_equal "bg-primary", budget_bar_class(30_000, 60_000, warn_percent: 80, breach_percent: 100)
    assert_equal "bg-warning", budget_bar_class(51_000, 60_000, warn_percent: 80, breach_percent: 100)   # 85%
    assert_equal "bg-error",   budget_bar_class(63_000, 60_000, warn_percent: 80, breach_percent: 100)   # 105%
  end

  test "band edges are inclusive, exactly like Budgets::Check" do
    assert_equal "bg-warning", budget_bar_class(48_000, 60_000, warn_percent: 80, breach_percent: 100)   # 80%
    assert_equal "bg-error",   budget_bar_class(60_000, 60_000, warn_percent: 80, breach_percent: 100)   # 100%
  end
end
