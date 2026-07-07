require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
  end

  test "index renders" do
    get categories_url
    assert_response :success
    assert_select "form#category_form"
  end

  test "create adds a category, scoped to the user" do
    assert_difference -> { @user.account.categories.count }, 1 do
      post categories_url, as: :turbo_stream, params: { category: { name: "Pets" } }
    end
  end

  test "citext uniqueness rejects 'mercado' vs an existing 'Mercado'" do
    @user.account.categories.create!(name: "Mercado")
    post categories_url, as: :turbo_stream, params: { category: { name: "mercado" } }
    assert_response :unprocessable_entity
    assert_equal 1, @user.account.categories.where("name ILIKE 'mercado'").count
  end

  test "deleting a category soft-deletes it; movements keep their category_id (name + suffix)" do
    cat  = @user.account.categories.create!(name: "Mercado")
    acct = @user.account.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    txn  = @user.account.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                      direction: "expense", category: cat, bank_account: acct)
    delete category_url(cat), as: :turbo_stream
    assert cat.reload.soft_deleted?
    assert_equal cat.id, txn.reload.category_id, "soft delete cascades to nothing — the link is kept"
    assert_not @user.account.categories.kept.exists?(cat.id), "gone from the kept list"
  end

  test "suggest returns the memory category for a known merchant" do
    cat = @user.account.categories.create!(name: "Restaurantes")
    @user.account.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                       direction: "expense", merchant: "iFood",
                                       category: cat, category_source: "user")
    get suggest_categories_url, params: { merchant: "IFOOD" }
    assert_response :success
    assert_equal cat.id, JSON.parse(response.body)["category_id"]
  end

  test "suggest is 204 on a miss and for machine-categorized history" do
    get suggest_categories_url, params: { merchant: "desconhecido" }
    assert_response :no_content

    cat = @user.account.categories.create!(name: "Transporte")
    @user.account.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                       direction: "expense", merchant: "Uber",
                                       category: cat, category_source: "ai")
    get suggest_categories_url, params: { merchant: "Uber" }
    assert_response :no_content
  end

  test "suggest never leaks another account's memory" do
    other = users(:english)
    cat = other.account.categories.create!(name: "Groceries")
    other.account.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                       direction: "expense", merchant: "Zaffari", created_by: other,
                                       category: cat, category_source: "user")
    get suggest_categories_url, params: { merchant: "Zaffari" }
    assert_response :no_content
  end

  test "restore re-seeds the 12 locale defaults, idempotently" do
    assert_difference -> { @user.account.categories.count }, 12 do
      post restore_categories_url
    end
    assert_no_difference -> { @user.account.categories.count } do
      post restore_categories_url
    end
  end

  test "rename in place via update" do
    cat = @user.account.categories.create!(name: "Mercado")
    patch category_url(cat), as: :turbo_stream, params: { category: { name: "Feira" } }
    assert_equal "Feira", cat.reload.name
  end

  test "create stores a chosen color and icon" do
    post categories_url, as: :turbo_stream,
         params: { category: { name: "Pets", color: "#22C55E", icon: "heart" } }
    cat = @user.account.categories.order(:id).last
    assert_equal "#22C55E", cat.color
    assert_equal "heart", cat.icon
  end

  test "update changes color and icon" do
    cat = @user.account.categories.create!(name: "Mercado")
    patch category_url(cat), as: :turbo_stream, params: { category: { color: "#EF4444", icon: "cart" } }
    assert_equal "#EF4444", cat.reload.color
    assert_equal "cart", cat.icon
  end

  test "a color or icon outside the curated set is rejected" do
    post categories_url, as: :turbo_stream, params: { category: { name: "Hax", color: "red; content:evil", icon: "skull" } }
    assert_response :unprocessable_entity
  end

  test "edit renders the color and icon pickers" do
    cat = @user.account.categories.create!(name: "Mercado")
    get edit_category_url(cat)
    assert_response :success
    assert_select "input[name='category[color]'][value='#3B82F6']"
    assert_select "input[name='category[icon]'][value='cart']"
  end

  test "seeded defaults come with a color and icon" do
    post restore_categories_url
    mercado = @user.account.categories.find_by(name: "Mercado")
    assert_equal "#22C55E", mercado.color
    assert_equal "cart", mercado.icon
  end

  test "update sets the monthly budget from a human reais string; blank clears it" do
    cat = @user.account.categories.create!(name: "Restaurantes")
    patch category_url(cat), as: :turbo_stream, params: { category: { monthly_budget_reais: "600,00" } }
    assert_equal 60_000, cat.reload.monthly_budget_cents

    patch category_url(cat), as: :turbo_stream, params: { category: { monthly_budget_reais: "" } }
    assert_nil cat.reload.monthly_budget_cents
  end

  test "a zero budget is rejected (must be positive when present)" do
    cat = @user.account.categories.create!(name: "Restaurantes")
    patch category_url(cat), as: :turbo_stream, params: { category: { monthly_budget_reais: "0,00" } }
    assert_response :unprocessable_entity
    assert_nil cat.reload.monthly_budget_cents
  end

  test "suggest_budget pre-fills the 3-month median as a reais string" do
    travel_to Time.utc(2026, 7, 15, 15, 0) do
      cat  = @user.account.categories.create!(name: "Restaurantes")
      bank = @user.account.bank_accounts.create!(institution: Institution.find_by(code: "260"))
      { 4 => 40_000, 5 => 42_000, 6 => 410_000 }.each do |month, cents|
        @user.account.transactions.create!(amount_cents: cents, occurred_on: Date.new(2026, month, 10),
                                           status: "posted", direction: "expense",
                                           category: cat, bank_account: bank)
      end

      get suggest_budget_category_url(cat)
      assert_response :success
      assert_equal "420,00", JSON.parse(response.body)["budget_reais"]
    end
  end

  test "suggest_budget is 204 with less than one full month of history" do
    cat = @user.account.categories.create!(name: "Restaurantes")
    get suggest_budget_category_url(cat)
    assert_response :no_content
  end
end
