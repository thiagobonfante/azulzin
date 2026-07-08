require "application_system_test_case"

class OnboardingAccountsTest < ApplicationSystemTestCase
  test "can add several bank accounts in a row via the picker" do
    user = users(:confirmed)

    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_button I18n.t("sessions.new.submit")

    # profile step
    assert_current_path onboarding_step_path("profile")
    fill_in "user_name", with: "Ana"
    fill_in "user_phone_national", with: "45988115410"
    click_button I18n.t("onboarding.profile.submit")

    # accounts step — add two in a row
    assert_current_path onboarding_step_path("accounts")
    add_account "Nubank"
    assert_selector "#bank_accounts_list", text: "Nubank"

    add_account "Itaú"
    assert_selector "#bank_accounts_list", text: "Itaú"

    assert_equal 2, user.account.bank_accounts.count
  end

  private
    def add_account(institution_name)
      within "#bank_account_form" do
        find("[data-institution-select-target='button']").click
      end
      find("li[data-institution-select-target='option']", text: institution_name).click
      within "#bank_account_form" do
        click_button I18n.t("bank_accounts.add")
      end
    end
end
