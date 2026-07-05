require "test_helper"

class RecurrenceTest < ActiveSupport::TestCase
  test "fixed_day clamps to the month length: day 31 in Feb 2026 → Feb 28" do
    assert_equal Date.new(2026, 2, 28), Recurrence.date_for("fixed_day", 31, Date.new(2026, 2, 1))
  end

  test "fixed_day day 10 → day 10" do
    assert_equal Date.new(2026, 3, 10), Recurrence.date_for("fixed_day", 10, Date.new(2026, 3, 1))
  end

  test "1º dia útil of Jan 2027 skips the Jan 1 holiday AND the weekend → Jan 4" do
    assert_equal Date.new(2027, 1, 4), Recurrence.date_for("nth_business_day", 1, Date.new(2027, 1, 1))
  end

  test "nth_business_day counts weekdays: 3rd business day of Aug 2026 (Sat 1st) → Aug 5" do
    assert_equal Date.new(2026, 8, 5), Recurrence.date_for("nth_business_day", 3, Date.new(2026, 8, 1))
  end

  test "unknown schedule kind raises" do
    assert_raises(ArgumentError) { Recurrence.date_for("weekly", 1, Date.new(2026, 1, 1)) }
  end

  test "the holiday table covers 2027..2032" do
    assert Recurrence::COVERED_YEARS.cover?(2027)
    assert Recurrence::COVERED_YEARS.cover?(2032)
  end
end
