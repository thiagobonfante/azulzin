require "test_helpers/e2e/browser_case"

# WEB-AUTH-01 + WEB-ONB-01: the single most important journey — a brand-new user signs up,
# the confirmation link signs them in, and the wizard walks profile → accounts → incomes →
# cards (finish) → dashboard (.plans/e2e/05 §1). Server-rendered assertions only.
class JourneysOnboardingTest < E2E::BrowserCase
  test "signup → confirm → full wizard → dashboard" do
    # WEB-AUTH-01 — signup, then the confirmation link both confirms and signs in.
    visit new_registration_path
    fill_in User.human_attribute_name(:email_address),         with: "novo@example.com"
    fill_in User.human_attribute_name(:password),              with: "password123"
    fill_in User.human_attribute_name(:password_confirmation), with: "password123"
    click_on I18n.t("registrations.new.submit")
    assert_text I18n.t("registrations.create.check_email")

    user = User.find_by!(email_address: "novo@example.com")
    visit email_verification_path(token: user.generate_token_for(:email_verification))

    # WEB-ONB-01 — profile step (name + phone required first).
    assert_current_path onboarding_step_path("profile")
    fill_in "user_name", with: "Ana"
    fill_in "user_phone_national", with: "45988115410"
    click_button I18n.t("onboarding.profile.submit")

    # accounts step — ≥1 required; add one through the institution picker, then continue.
    assert_current_path onboarding_step_path("accounts")
    add_account "Nubank"
    assert_selector "#bank_accounts_list", text: "Nubank"
    click_button I18n.t("onboarding.accounts.continue")

    # incomes step — ≥1 required; add a salary tied to the account, then continue.
    assert_current_path onboarding_step_path("incomes")
    within "#income_form" do
      fill_in "income_name", with: "Salário"
      fill_in "income_amount_reais", with: "5.000,00"
      find("[data-institution-select-target='button']").click
    end
    find("li[data-institution-select-target='option']", text: "Nubank").click
    within "#income_form" do
      # Wait for the picker to commit before submitting — else the income posts without a
      # bank_account_id and validation-fails intermittently (system-test race).
      assert_selector "[data-institution-select-target='button']", text: "Nubank"
      click_button I18n.t("incomes.add")
    end
    assert_selector "#incomes_list", text: "Salário"
    click_button I18n.t("onboarding.incomes.continue")

    # cards step — optional; finish straight to the app.
    assert_current_path onboarding_step_path("cards")
    click_button I18n.t("onboarding.cards.finish")

    # the hub: onboarded, greeted by first name.
    assert_text I18n.t("dashboard.greeting", name: "Ana")
    assert user.reload.onboarded?
    assert_equal 1, user.account.bank_accounts.kept.count
    assert_equal 1, user.account.incomes.kept.count
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
