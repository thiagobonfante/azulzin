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
    assert_difference -> { @user.categories.count }, 1 do
      post categories_url, as: :turbo_stream, params: { category: { name: "Pets" } }
    end
  end

  test "citext uniqueness rejects 'mercado' vs an existing 'Mercado'" do
    @user.categories.create!(name: "Mercado")
    post categories_url, as: :turbo_stream, params: { category: { name: "mercado" } }
    assert_response :unprocessable_entity
    assert_equal 1, @user.categories.where("name ILIKE 'mercado'").count
  end

  test "deleting a category nullifies its movements, never destroys them" do
    cat  = @user.categories.create!(name: "Mercado")
    acct = @user.bank_accounts.create!(institution: Institution.find_by(code: "260"))
    txn  = @user.transactions.create!(amount_cents: 100, occurred_on: Date.current, status: "posted",
                                      direction: "expense", category: cat, bank_account: acct)
    delete category_url(cat), as: :turbo_stream
    assert_nil txn.reload.category_id
    assert Transaction.exists?(txn.id)
  end

  test "restore re-seeds the 12 locale defaults, idempotently" do
    assert_difference -> { @user.categories.count }, 12 do
      post restore_categories_url
    end
    assert_no_difference -> { @user.categories.count } do
      post restore_categories_url
    end
  end

  test "rename in place via update" do
    cat = @user.categories.create!(name: "Mercado")
    patch category_url(cat), as: :turbo_stream, params: { category: { name: "Feira" } }
    assert_equal "Feira", cat.reload.name
  end
end
