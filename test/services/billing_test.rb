require "test_helper"

# The R2/R11 closing-rule date math. The table below is 02 §3.1 (worked-example table)
# reproduced VERBATIM — the correctness kernel of the whole billing phase.
class BillingTest < ActiveSupport::TestCase
  def card(d:, f: 7) = CreditCard.new(bill_due_day: d, closing_offset_days: f)

  # [config, purchase date, expected billing_month] — 02 §3.1 rows 1–10 (11 is unconfigured).
  ROWS = [
    [ { d: 10, f: 10 }, "2026-07-03", "2026-08-01" ],  # 1 founder R11 example
    [ { d: 10, f: 7  }, "2026-07-03", "2026-07-01" ],  # 2 founder R2 boundary (ON closing day)
    [ { d: 10, f: 7  }, "2026-07-04", "2026-08-01" ],  # 3 day 4 onward rolls
    [ { d: 31, f: 7  }, "2026-02-10", "2026-02-01" ],  # 4 short-month clamp
    [ { d: 31, f: 7  }, "2026-02-25", "2026-03-01" ],  # 5
    [ { d: 30, f: 7  }, "2028-02-21", "2028-02-01" ],  # 6 leap year
    [ { d: 5,  f: 10 }, "2026-07-01", "2026-08-01" ],  # 7 closing in prior month
    [ { d: 5,  f: 9  }, "2026-12-28", "2027-02-01" ],  # 8 year rollover
    [ { d: 1,  f: 28 }, "2026-07-20", "2026-09-01" ],  # 9 double advance
    [ { d: 10, f: 0  }, "2026-07-10", "2026-07-01" ]   # 10 zero offset, ON due date
  ].freeze

  ROWS.each_with_index do |(cfg, purchase, expected), i|
    test "row #{i + 1}: d=#{cfg[:d]} f=#{cfg[:f]} bought #{purchase} → #{expected}" do
      c = card(**cfg)
      assert_equal Date.parse(expected), Billing.billing_month_for(c, Date.parse(purchase))
      assert_equal Date.parse(expected), c.billing_month_for(Date.parse(purchase)) # delegation
    end
  end

  test "row 11: an unconfigured card falls back to the purchase month" do
    c = card(d: nil)
    c.bill_due_day = nil
    assert_not c.billing_configured?
    assert_equal Date.new(2026, 7, 1), Billing.billing_month_for(c, Date.new(2026, 7, 3))
  end

  # Property tests across a config × month matrix (02 §3.1).
  test "a purchase ON the closing date stays; the next day rolls to a later bill" do
    [ [ 10, 10 ], [ 10, 7 ], [ 31, 7 ], [ 5, 9 ], [ 1, 28 ], [ 10, 0 ] ].each do |d, f|
      c = card(d: d, f: f)
      (1..12).each do |mo|
        m = Date.new(2026, mo, 1)
        closing = Billing.closing_date(c, m)
        assert_equal m, Billing.billing_month_for(c, closing), "closing #{closing} maps back to #{m}"
        assert_operator Billing.billing_month_for(c, closing + 1), :>, m, "day after #{closing} rolls forward"
      end
    end
  end

  test "pure record: computing billing months never writes anything" do
    c = card(d: 10, f: 7)
    assert_no_changes -> { c.changed? } do
      Billing.billing_month_for(c, Date.new(2026, 7, 4))
    end
  end
end
