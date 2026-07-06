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

  test "deleting a category nullifies its movements, never destroys them" do
    cat  = @user.account.categories.create!(name: "Mercado")
    acct = @user.account.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    txn  = @user.account.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                      direction: "expense", category: cat, bank_account: acct)
    delete category_url(cat), as: :turbo_stream
    assert_nil txn.reload.category_id
    assert Transaction.exists?(txn.id)
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
end
