require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "root renders the home page" do
    get root_url
    assert_response :success
    # Home renders in the default locale (pt-BR); assert on the resolved key, not hardcoded copy.
    assert_select "h1", /#{Regexp.escape(I18n.t("pages.home.hero_title_1"))}/
  end

  test "locale is forced to pt-BR even when another locale is explicitly requested" do
    get root_url(locale: "en-US")
    assert_response :success
    assert_select "h1", /#{Regexp.escape(I18n.t("pages.home.hero_title_1", locale: :"pt-BR"))}/
    # The en-US copy must never leak through while the locale is force-pinned.
    assert_no_match(/#{Regexp.escape(I18n.t("pages.home.hero_title_1", locale: :"en-US"))}/, response.body)
  end
end
