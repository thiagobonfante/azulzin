require "test_helpers/e2e/browser_case"

# WEB-NA-01 (.plans/mobile/01 §8): the native-shell journey, faked with the Hotwire Native
# UA at the browser level — sign-in → chrome-less layout → entry-drawer add → exact centavos.
class JourneysNativeAppTest < E2E::BrowserCase
  NATIVE_UA = "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; Azulzin/1.0.0".freeze

  # Own driver NAME, not just own options: driven_by(:selenium, ...) re-registers the shared
  # :selenium driver and the native UA would leak into every other system test in the process.
  Capybara.register_driver :native_ua_chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless=new")
    options.add_argument("--window-size=1400,1400")
    options.add_argument("--user-agent=#{NATIVE_UA}")
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end
  driven_by :native_ua_chrome

  test "WEB-NA-01: native UA signs in, adds a transaction in the drawer, ledger shows exact centavos" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)

    assert_no_selector ".drawer"   # the chrome-less native layout — no sidebar/drawer

    visit transactions_path
    find("a[href*='transactions/new']", text: I18n.t("transactions.ledger.add")).click
    within "#entry_form" do
      # Bank-app money mask: typed digits are centavos (54,90).
      find_field(I18n.t("transactions.row.amount")).send_keys "5490"
      fill_in I18n.t("transactions.row.merchant"), with: "Padaria Native"
      find("button[data-method='pix']").click
      assert_selector "[data-entry-instrument-target='display']", text: s.itau.display_name
      click_button I18n.t("transactions.new.submit")
    end

    assert_no_selector "dialog.modal[open]"   # saved → drawer closed (UI settles before the DB read)
    assert_text "Padaria Native"
    assert_brl 5_490, find("#ledger_list").text

    txn = s.account.transactions.sole
    assert_equal 5_490, txn.amount_cents
    assert_equal s.itau, txn.bank_account
  end
end
