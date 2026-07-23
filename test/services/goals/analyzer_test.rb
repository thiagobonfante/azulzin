require "test_helper"

# Analyzer snapshots the household baseline from its own ledger (.plans/goals 01 §4). Covers the
# data-sufficiency ladder, median-beats-spike (trap #7), billing-month bucketing (trap #5),
# capacity-includes-guardado (trap #6), and flexibility resolution.
class Goals::AnalyzerTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # window is the 3 full months before as_of: Apr, May, Jun 2026.
  AS_OF = Date.new(2026, 7, 15)
  WIN   = [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ].freeze

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @savings  = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    travel_to Time.utc(2026, 7, 15, 12)   # window Apr–Jun 2026 stays fully in the past
  end

  teardown { travel_back }

  def analyze = Goals::Analyzer.call(@account, as_of: AS_OF)

  def spend!(category:, month:, cents:, commitment: nil, count: 1)
    count.times do
      @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                    category:, commitment:, occurred_on: month, billing_month: month,
                                    billing_month_manual: true, bank_account: @checking)
    end
  end

  def income!(month:, cents:)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: cents,
                                  occurred_on: month, billing_month: month, billing_month_manual: true,
                                  bank_account: @checking)
  end

  def transfer_to_savings!(month:, cents:)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @savings,
                                  occurred_on: month, billing_month: month, billing_month_manual: true)
  end

  test "empty account degrades to :insufficient and never raises" do
    assert_equal :insufficient, analyze.sufficiency
    refute analyze.per_category_caps?
  end

  test "one month of data is :thin" do
    cat = @account.categories.create!(name: "Restaurantes")
    spend!(category: cat, month: WIN.last, cents: 5_000, count: 12)
    assert_equal :thin, analyze.sufficiency
  end

  test "two months with ≥10 posted expenses each is :ok" do
    cat = @account.categories.create!(name: "Restaurantes")
    spend!(category: cat, month: WIN[1], cents: 5_000, count: 10)
    spend!(category: cat, month: WIN[2], cents: 5_000, count: 10)
    assert_equal :ok, analyze.sufficiency
  end

  test "median beats a one-off spike (trap #7): [400, 420, 4100] → 420" do
    cat = @account.categories.create!(name: "Saúde")
    spend!(category: cat, month: WIN[0], cents: 400)
    spend!(category: cat, month: WIN[1], cents: 420)
    spend!(category: cat, month: WIN[2], cents: 4_100)   # a vet bill spike
    stat = analyze.categories.find { |c| c.name == "Saúde" }
    assert_equal 420, stat.median_cents
  end

  test "spend is bucketed by billing_month, never occurred_on (trap #5)" do
    cat = @account.categories.create!(name: "Restaurantes")
    # occurred in June but billed to July (a card fatura) → outside the Apr–Jun window entirely.
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 9_999,
                                  category: cat, occurred_on: Date.new(2026, 6, 28),
                                  billing_month: Date.new(2026, 7, 1), billing_month_manual: true,
                                  bank_account: @checking)
    spend!(category: cat, month: WIN[1], cents: 5_000)   # a real May row inside the window
    stat = analyze.categories.find { |c| c.name == "Restaurantes" }
    assert_equal 5_000, stat.median_cents                # the July-billed row is excluded
    assert_equal 1, stat.months_present
  end

  test "capacity base = median(entradas − saídas − faturas) and equals sobra + guardado (trap #6)" do
    WIN.each do |m|
      income!(month: m, cents: 500_000)
      spend!(category: @account.categories.create!(name: "M#{m.month}"), month: m, cents: 400_000)
      transfer_to_savings!(month: m, cents: 100_000)     # an existing saver
    end
    profile = analyze
    # each month: 500_000 − 400_000 − 0 = 100_000 (= the guardado), sobra itself ≈ 0
    assert_equal 100_000, profile.median_capacity_base_cents
    assert_equal 100_000, profile.median_saved_cents
    assert_equal 500_000, profile.median_income_cents
  end

  test "uncategorized at 45% of trimmable spend (just over the limit) flips off per-category caps" do
    cat = @account.categories.create!(name: "Restaurantes")
    spend!(category: cat, month: WIN[1], cents: 55_000)
    spend!(category: nil, month: WIN[1], cents: 45_000)   # 45% uncategorized → total-cap-only
    refute analyze.per_category_caps?
  end

  test "uncategorized below the 40% limit keeps per-category caps on" do
    cat = @account.categories.create!(name: "Restaurantes")
    spend!(category: cat, month: WIN[1], cents: 70_000)
    spend!(category: nil, month: WIN[1], cents: 30_000)   # 30% uncategorized
    assert analyze.per_category_caps?
  end

  test "flexibility resolves by the seeded-name map" do
    flex = @account.categories.create!(name: "Restaurantes")
    ess  = @account.categories.create!(name: "Mercado")
    spend!(category: flex, month: WIN[1], cents: 5_000)
    spend!(category: ess,  month: WIN[1], cents: 5_000)
    profile = analyze
    assert profile.categories.find { |c| c.name == "Restaurantes" }.flexible?
    refute profile.categories.find { |c| c.name == "Mercado" }.flexible?
  end

  test "a cached categories.flexibility column wins over the name map" do
    cat = @account.categories.create!(name: "Mercado", flexibility: "flexible")
    spend!(category: cat, month: WIN[1], cents: 5_000)
    assert analyze.categories.find { |c| c.name == "Mercado" }.flexible?
  end

  test "only the commitment-less portion is trimmable" do
    cat = @account.categories.create!(name: "Restaurantes")
    commitment = @account.commitments.create!(kind: "subscription", bank_account: @checking,
                                              amount_cents: 3_000, name: "Streaming", starts_on: WIN[0])
    spend!(category: cat, month: WIN[1], cents: 3_000, commitment: commitment)  # committed
    spend!(category: cat, month: WIN[1], cents: 5_000)                           # discretionary
    stat = analyze.categories.find { |c| c.name == "Restaurantes" }
    assert_equal 8_000, stat.median_cents
    assert_equal 5_000, stat.trimmable_median_cents
  end
end
