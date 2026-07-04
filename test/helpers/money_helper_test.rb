require "test_helper"

class MoneyHelperTest < ActionView::TestCase
  test "brl pins the R$ unit in every locale (never renders reais as $)" do
    I18n.with_locale(:"pt-BR") { assert_match(/R\$/, brl(123456)) }
    I18n.with_locale(:"en-US") { assert_match(/R\$/, brl(123456)) }   # would be "$" without the unit pin
  end

  test "brl formats integer cents with pt-BR separators" do
    assert_match(/R\$\s*1\.234,56/, brl(123456))
    assert_match(/R\$\s*0,00/, brl(0))
  end
end
