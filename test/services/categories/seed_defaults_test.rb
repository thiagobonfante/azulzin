require "test_helper"

class Categories::SeedDefaultsTest < ActiveSupport::TestCase
  test "seeds exactly 12 categories in the user's locale, idempotently" do
    user = users(:confirmed) # pt-BR
    assert_equal 0, user.account.categories.count
    Categories::SeedDefaults.call(user.account, locale: user.locale)
    Categories::SeedDefaults.call(user.account, locale: user.locale) # run twice — restores nothing extra
    assert_equal 12, user.account.categories.count
    assert_includes user.account.categories.pluck(:name), "Mercado"
    assert_equal (0..11).to_a, user.account.categories.order(:position).pluck(:position)
  end

  test "seeds English names for an en-US user" do
    user = users(:english)
    Categories::SeedDefaults.call(user.account, locale: user.locale)
    names = user.account.categories.pluck(:name)
    assert_includes names, "Groceries"
    assert_not_includes names, "Mercado"
  end

  test "both locale arrays are the same length (seed-time invariant)" do
    assert_equal I18n.t("categories.defaults", locale: :en).length,
                 I18n.t("categories.defaults", locale: :"pt-BR").length
  end
end
