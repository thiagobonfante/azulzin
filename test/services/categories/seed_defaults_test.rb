require "test_helper"

class Categories::SeedDefaultsTest < ActiveSupport::TestCase
  test "seeds exactly 12 categories in the user's locale, idempotently" do
    user = users(:confirmed) # pt-BR
    assert_equal 0, user.categories.count
    Categories::SeedDefaults.call(user)
    Categories::SeedDefaults.call(user) # run twice — restores nothing extra
    assert_equal 12, user.categories.count
    assert_includes user.categories.pluck(:name), "Mercado"
    assert_equal (0..11).to_a, user.categories.order(:position).pluck(:position)
  end

  test "seeds English names for an en-US user" do
    user = users(:english)
    Categories::SeedDefaults.call(user)
    names = user.categories.pluck(:name)
    assert_includes names, "Groceries"
    assert_not_includes names, "Mercado"
  end

  test "both locale arrays are the same length (seed-time invariant)" do
    assert_equal I18n.t("categories.defaults", locale: :en).length,
                 I18n.t("categories.defaults", locale: :"pt-BR").length
  end
end
