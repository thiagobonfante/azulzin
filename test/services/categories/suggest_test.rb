require "test_helper"

class Categories::SuggestTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
    Categories::SeedDefaults.call(@account, locale: "pt-BR")
    @mercado      = @account.categories.find_by(name: "Mercado")
    @restaurantes = @account.categories.find_by(name: "Restaurantes")
  end

  def spend!(merchant, category: nil, source: "user", days_ago: 0)
    @account.transactions.create!(
      created_by: @user, direction: "expense", status: "posted", confirmed_at: Time.current,
      amount_cents: 1_000, merchant: merchant, occurred_on: Date.current - days_ago,
      category_id: category&.id, category_source: (category ? source : nil), source: "manual"
    )
  end

  test "repeat human-categorized merchant suggests its category (accent/case-insensitive)" do
    2.times { |i| spend!("iFood", category: @restaurantes, days_ago: i) }
    result = Categories::Suggest.call(account: @account, merchant: "IFOOD ")
    assert_equal @restaurantes, result.category
    assert_equal 1.0, result.share
    assert_equal 2, result.sample_size
  end

  test "a single human-categorized row is a valid sample (1/1 = 100%)" do
    spend!("Zaffari", category: @mercado)
    assert_equal @mercado, Categories::Suggest.call(account: @account, merchant: "zaffari").category
  end

  test "modal share boundary: 3/5 fires, 2/5 does not" do
    3.times { |i| spend!("Amazon", category: @mercado, days_ago: i) }
    2.times { |i| spend!("Amazon", category: @restaurantes, days_ago: 10 + i) }
    assert_equal @mercado, Categories::Suggest.call(account: @account, merchant: "amazon").category

    spend!("Shopee", category: @mercado)
    spend!("Shopee", category: @mercado, days_ago: 1)
    spend!("Shopee", category: @restaurantes, days_ago: 2)
    spend!("Shopee", category: @account.categories.find_by(name: "Lazer"), days_ago: 3)
    spend!("Shopee", category: @account.categories.find_by(name: "Vestuário"), days_ago: 4)
    assert_nil Categories::Suggest.call(account: @account, merchant: "shopee") # 2/5 < 0.6
  end

  test "machine-assigned rows never feed memory" do
    spend!("Uber", category: @mercado, source: "ai")
    spend!("Uber", category: @mercado, source: "memory", days_ago: 1)
    assert_nil Categories::Suggest.call(account: @account, merchant: "uber")
  end

  test "legacy rows (null category_source) are excluded until a human touches them" do
    spend!("Posto Ipiranga", category: @mercado, source: nil)
    assert_nil Categories::Suggest.call(account: @account, merchant: "posto ipiranga")
  end

  test "LOOKBACK window: only the 20 most recent rows count" do
    20.times { |i| spend!("Padaria", category: @restaurantes, days_ago: i) }
    30.times { |i| spend!("Padaria", category: @mercado, days_ago: 30 + i) }  # older, crowded out
    assert_equal @restaurantes, Categories::Suggest.call(account: @account, merchant: "padaria").category
  end

  test "a since-deleted category yields nil" do
    spend!("Farmácia", category: @account.categories.find_by(name: "Saúde"))
    @account.categories.find_by(name: "Saúde").soft_delete!(by: @user)
    assert_nil Categories::Suggest.call(account: @account, merchant: "farmácia")
  end

  test "blank merchant yields nil" do
    assert_nil Categories::Suggest.call(account: @account, merchant: nil)
    assert_nil Categories::Suggest.call(account: @account, merchant: "  ")
  end

  test "soft-deleted transactions are ignored" do
    t = spend!("Cinema", category: @restaurantes)
    t.soft_delete!(by: @user)
    assert_nil Categories::Suggest.call(account: @account, merchant: "cinema")
  end
end
