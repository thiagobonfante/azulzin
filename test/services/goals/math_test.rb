require "test_helper"

# Money-math correctness traps #1 and #4 (.plans/goals 01 §8): one documented half-up rounding
# rule, cents-exact division, and NO Float anywhere in the goals engine.
class Goals::MathTest < ActiveSupport::TestCase
  test "median mirrors Budgets::Suggest (odd → middle, even → integer mean of the two middle)" do
    assert_equal 420, Goals.median([400, 420, 4100])          # median beats the spike (trap #7)
    assert_equal 0,   Goals.median([])
    assert_equal 150, Goals.median([100, 200])               # even count → (100+200)/2
  end

  test "median of four is the mean of the two middle values" do
    assert_equal 250, Goals.median([100, 200, 300, 400])
  end

  test "prorate is one documented BigDecimal half-up rule" do
    assert_equal 1111, Goals.prorate(3333, 1, 3)     # 3333/3 = 1111 exactly
    assert_equal 55,   Goals.prorate(100, 17, 31)    # 1700/31 = 54.83… → half-up 55
    assert_equal 0,    Goals.prorate(100, 5, 0)      # zero denominator → 0, never raises
  end

  test "ceil_div never undershoots (required-monthly trap #2)" do
    assert_equal 352_942, Goals.ceil_div(6_000_000, 17)
    assert_equal 34,      Goals.ceil_div(100, 3)
    # property: monthly × months ≥ remaining, for adversarial pairs
    [[6_000_000, 17], [100, 3], [1, 48], [100_001, 3], [999_999, 7], [50_000, 1]].each do |remaining, months|
      monthly = Goals.ceil_div(remaining, months)
      assert_operator monthly * months, :>=, remaining, "ceil_div(#{remaining},#{months}) undershot"
      assert_operator (monthly - 1) * months, :<, remaining, "ceil_div(#{remaining},#{months}) overshot by a whole month"
    end
  end

  test "months_between counts whole months (Jul 2026 → Dec 2027 = 17)" do
    assert_equal 17, Goals.months_between(Date.new(2026, 7, 1), Date.new(2027, 12, 1))
    assert_equal 1,  Goals.months_between(Date.new(2026, 7, 1), Date.new(2026, 8, 1))
    assert_equal 0,  Goals.months_between(Date.new(2026, 7, 1), Date.new(2026, 7, 1))
  end

  test "cv_squared stays in BigDecimal and flags irregular income" do
    steady = [500_000, 505_000, 495_000]
    spiky  = [200_000, 900_000, 100_000]
    assert Goals.cv_squared(steady) < Goals::INCOME_IRREGULAR_CV**2
    assert Goals.cv_squared(spiky)  > Goals::INCOME_IRREGULAR_CV**2
    assert_kind_of BigDecimal, Goals.cv_squared(steady)
  end

  test "no Float or to_f anywhere in the goals engine (trap #4 grep gate)" do
    files = Dir[Rails.root.join("app/services/goals.rb")] + Dir[Rails.root.join("app/services/goals/**/*.rb")]
    assert files.size >= 4, "expected the goals engine files to exist"
    files.each do |f|
      code = File.read(f).gsub(/#.*$/, "")   # strip comments (the engine has no # inside strings)
      assert_no_match(/\.to_f\b/, code, "#{f} uses .to_f")
      assert_no_match(/\bFloat\s*[(:]/, code, "#{f} coerces via Float() or Float::")
    end
  end
end
