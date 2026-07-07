require "test_helper"

# The deterministic budget suggester (up-tier 03 §3): median — never mean — of the
# trailing 3 FULL billing months, per category.
class Budgets::SuggestTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account = users(:confirmed).account
    @bank    = BankAccount.create!(account: @account, institution: Institution.find_by(code: "260"))
    @cat     = @account.categories.create!(name: "Restaurantes")
    travel_to Time.utc(2026, 7, 15, 15, 0)   # trailing full months: Apr, May, Jun
  end

  def spend!(cents, on:, category: @cat)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                  occurred_on: on, category: category, bank_account: @bank)
  end

  test "median, never mean: [400, 420, 4100] suggests 420 (the vet-bill spike guard)" do
    spend!(40_000,  on: Date.new(2026, 4, 10))
    spend!(42_000,  on: Date.new(2026, 5, 10))
    spend!(410_000, on: Date.new(2026, 6, 10))

    assert_equal 42_000, Budgets::Suggest.call(@account)[@cat.id]
  end

  test "no full month of history → no suggestion for the category" do
    assert_nil Budgets::Suggest.call(@account)[@cat.id]
  end

  test "the current, partial month never contaminates the baseline" do
    spend!(999_900, on: Date.new(2026, 7, 10))

    assert_nil Budgets::Suggest.call(@account)[@cat.id]
  end

  test "an even count takes the integer mean of the middle pair" do
    spend!(40_000, on: Date.new(2026, 5, 10))
    spend!(50_000, on: Date.new(2026, 6, 10))

    assert_equal 45_000, Budgets::Suggest.call(@account)[@cat.id]
  end

  test "uncategorized spend suggests nothing" do
    spend!(30_000, on: Date.new(2026, 6, 10), category: nil)

    assert_empty Budgets::Suggest.call(@account)
  end
end
