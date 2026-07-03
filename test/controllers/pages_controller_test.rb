require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "root renders the home page" do
    get root_url
    assert_response :success
    # Home renders in the default locale (pt-BR); assert on the resolved key, not hardcoded copy.
    assert_select "h1", /#{Regexp.escape(I18n.t("pages.home.hero_title_1"))}/
  end
end
