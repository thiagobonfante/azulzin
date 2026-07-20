require "test_helper"

# .plans/mobile Phase 0: the Hotwire Native groundwork, verified by faking the shells'
# User-Agent. Web behavior must be byte-identical (the whole suite is that regression pin).
class NativeVariantTest < ActionDispatch::IntegrationTest
  NATIVE_UA = "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; Azulzin/1.0.0"

  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
  end

  def native = { "User-Agent" => NATIVE_UA }

  test "native UA renders the chrome-less app layout, web keeps the drawer" do
    get dashboard_url, headers: native
    assert_response :success
    assert_select ".drawer", count: 0          # no sidebar/drawer chrome
    assert_select "dialog[data-controller=confirm]"   # confirm dialog stays

    get dashboard_url
    assert_select ".drawer"                    # web unchanged
  end

  test "menu page lists every Mais destination" do
    get menu_url, headers: native
    assert_response :success
    [ commitments_path, bank_accounts_path, incomes_path, credit_cards_path,
      categories_path, notification_preferences_path, new_export_path, account_path ].each do |path|
      assert_select "a[href='#{path}']"
    end
    assert_select "form[action='#{session_path}'] button"       # Sair
    assert_select "a[href='#{admin_whatsapp_connection_path}']", count: 0   # not an admin
  end

  test "menu page renders for web too" do
    get menu_url
    assert_response :success
  end

  test "chat stub responds with the empty thread" do
    get chat_url, headers: native
    assert_response :success
    assert_select "#chat_messages"
    assert_includes response.body, I18n.t("chat.show.empty", locale: :"pt-BR")
  end

  test "auth screens set a title and hide the Google button under the native variant" do
    sign_out
    get new_session_url, headers: native
    assert_select "title", I18n.t("sessions.new.title", locale: :"pt-BR")
    assert_select "form[action='/auth/google_oauth2']", count: 0

    get new_registration_url, headers: native
    assert_select "form[action='/auth/google_oauth2']", count: 0

    get new_session_url
    assert_select "form[action='/auth/google_oauth2']"   # web keeps Google
  end

  test "native registration notice says the verification link opens in the browser" do
    sign_out
    post registration_url, headers: native, params: { user: {
      email_address: "native@example.com", password: "password123", password_confirmation: "password123" } }
    assert_redirected_to new_session_url
    assert_equal I18n.t("registrations.create.check_email_native", locale: :"pt-BR"), flash[:notice]
  end

  test "path configuration serves per-platform JSON with a cache header, unauthenticated" do
    sign_out
    %w[ios_v1 android_v1].each do |platform|
      get "/configurations/#{platform}.json"
      assert_response :success
      json = JSON.parse(response.body)
      assert json.key?("settings")
      rules = json.fetch("rules")
      assert rules.first.fetch("patterns").include?("/new$")
      assert_equal "modal", rules.first.dig("properties", "context")
      # Auth screens must override the generic modal rule AFTER it (later rules win):
      # a modal /session/new hides the Android tab bar on the signed-out cold start.
      auth = rules.find { |r| r.fetch("patterns").include?("^/session/new$") }
      assert_equal "default", auth.dig("properties", "context")
      assert rules.index(auth) > 0, "the auth exception must come after the generic modal rule"
      assert_includes response.headers["Cache-Control"], "max-age=300"
      assert_includes response.headers["Cache-Control"], "public"
    end
  end

  test "unknown path-config platform does not route" do
    sign_out
    get "/configurations/windows_v1.json"
    assert_response :not_found
  end

  test "an edit-form save recedes for native and redirects for web" do
    ba = @user.account.bank_accounts.create!(institution: Institution.find_by!(code: "341"), nickname: "Itaú")

    patch bank_account_url(ba), headers: native, params: { bank_account: { nickname: "Itaú Novo" } }
    assert_response :redirect
    assert_includes response.location, "recede_historical_location"

    patch bank_account_url(ba), params: { bank_account: { nickname: "Itaú Web" } }
    assert_redirected_to bank_accounts_url
  end
end
