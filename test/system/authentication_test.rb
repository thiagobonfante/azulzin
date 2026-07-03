require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  # Labels/copy are asserted via resolved I18n keys (default test locale is pt-BR),
  # so the test survives wording changes and renders in the real UI language.
  test "sign up is gated on confirmation; the link both confirms and signs you in" do
    visit new_registration_path
    fill_in User.human_attribute_name(:email_address),         with: "sys@example.com"
    fill_in User.human_attribute_name(:password),              with: "password123"
    fill_in User.human_attribute_name(:password_confirmation), with: "password123"
    click_on I18n.t("registrations.new.submit")

    # Landed on sign-in with the "check your email" gate — NOT signed into the app.
    assert_text I18n.t("registrations.create.check_email")

    # The confirmation link both confirms the account and signs the user in.
    user = User.find_by(email_address: "sys@example.com")
    visit email_verification_path(token: user.generate_token_for(:email_verification))
    assert_text I18n.t("layout.nav.sign_out") # nav now shows the signed-in state
  end
end
