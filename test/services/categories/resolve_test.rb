require "test_helper"

class Categories::ResolveTest < ActiveSupport::TestCase
  setup do
    @account = users(:confirmed).account
    Categories::SeedDefaults.call(@account, locale: "pt-BR")
  end

  test "exact normalized-name match wins (accents/case ignored)" do
    saude = @account.categories.find_by(name: "Saúde")
    assert_equal saude, Categories::Resolve.call(account: @account, label: "saude")
    assert_equal saude, Categories::Resolve.call(account: @account, label: "  SAÚDE ")
  end

  test "fuzzy match at or above MATCH_MIN resolves" do
    assert_equal @account.categories.find_by(name: "Restaurantes"),
                 Categories::Resolve.call(account: @account, label: "restaurante")
  end

  test "below MATCH_MIN returns nil, never a weak guess" do
    assert_nil Categories::Resolve.call(account: @account, label: "xyzzy")
    assert_nil Categories::Resolve.call(account: @account, label: "criptomoedas")
  end

  test "blank and nil labels return nil" do
    assert_nil Categories::Resolve.call(account: @account, label: nil)
    assert_nil Categories::Resolve.call(account: @account, label: "   ")
  end

  test "soft-deleted categories are never returned" do
    saude = @account.categories.find_by(name: "Saúde")
    saude.soft_delete!(by: users(:confirmed))
    assert_nil Categories::Resolve.call(account: @account, label: "saúde")
  end

  test "another account's categories are invisible" do
    other = users(:english).account
    Categories::SeedDefaults.call(other, locale: "en-US")
    assert_nil Categories::Resolve.call(account: @account, label: "Groceries")
  end
end
