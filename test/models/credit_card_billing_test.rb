require "test_helper"

# Card-config recompute (both cases) and the derived committed-usage figures (02 §6).
class CreditCardBillingTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @card = CreditCard.create!(account: @user.account, institution: @inst) # unconfigured
  end

  def expense(occurred, **attrs)
    @user.account.transactions.create!({ amount_cents: 1_000, occurred_on: occurred, status: "posted",
                                 direction: "expense", credit_card: @card }.merge(attrs))
  end

  test "billing_configured? keys on bill_due_day alone; billing_month_for delegates to Billing" do
    assert_not @card.billing_configured?
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    assert @card.billing_configured?
    assert_equal Billing.billing_month_for(@card, Date.new(2026, 7, 4)), @card.billing_month_for(Date.new(2026, 7, 4))
  end

  test "first-time configuration re-buckets ALL non-manual rows off the calendar-month fallback" do
    old = expense(Date.new(2026, 3, 4))  # unconfigured → calendar month March
    assert_equal Date.new(2026, 3, 1), old.billing_month
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    @card.recompute_billing_months!(first_time: true)
    assert_equal Date.new(2026, 4, 1), old.reload.billing_month  # March 4, d10/f7 → April fatura
  end

  test "a subsequent edit recomputes only the open bill and later; closed faturas are preserved" do
    travel_to Date.new(2026, 7, 20) do
      @card.update!(bill_due_day: 10, closing_offset_days: 7)
      @card.recompute_billing_months!(first_time: true)
      closed = expense(Date.new(2026, 5, 4)); closed.reload  # June fatura (closed, < open bill July)
      open   = expense(Date.new(2026, 7, 4)); open.reload    # August fatura (>= open)
      closed_before = closed.billing_month

      @card.update!(bill_due_day: 15)
      @card.recompute_billing_months!(first_time: false)
      assert_equal closed_before, closed.reload.billing_month              # untouched
      assert_equal @card.billing_month_for(open.occurred_on), open.reload.billing_month
    end
  end

  test "recompute skips manually-moved rows and preserves the parcel stagger" do
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    manual = expense(Date.new(2026, 7, 4))
    manual.update!(billing_month: Date.new(2027, 1, 1), billing_month_manual: true)
    @card.recompute_billing_months!(first_time: true)
    assert_equal Date.new(2027, 1, 1), manual.reload.billing_month
  end

  test "used_cents is committed-not-yet-paid over the open bill and later" do
    travel_to Date.new(2026, 7, 20) do
      @card.update!(bill_due_day: 10, closing_offset_days: 7, credit_limit_cents: 100_000)
      expense(Date.new(2026, 7, 4), amount_cents: 30_000)   # August fatura (open bill+)
      expense(Date.new(2026, 5, 4), amount_cents: 90_000)   # June fatura (before open → considered paid)
      assert_equal 30_000, @card.reload.used_cents
      assert_in_delta 0.3, @card.usage_ratio, 0.001
    end
  end
end
