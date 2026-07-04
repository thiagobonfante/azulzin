require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    sign_in_as(@user)
    @nubank = Institution.find_by(code: "260")
  end

  def complete_profile
    @user.update!(name: "Ana", phone: "5511912345678")
  end

  test "requires authentication" do
    sign_out
    get onboarding_url
    assert_redirected_to new_session_url
  end

  test "onboarding resolves to the profile step first" do
    get onboarding_url
    assert_redirected_to onboarding_step_url("profile")
  end

  test "cannot jump ahead to accounts before the profile is complete" do
    get onboarding_step_url("accounts")
    assert_redirected_to onboarding_step_url("profile")
  end

  test "profile step joins country code + national number then advances to accounts" do
    patch onboarding_step_url("profile"), params: { user: { name: "Ana", country_code: "55", phone_national: "(45) 98811-5410" } }
    assert_redirected_to onboarding_step_url("accounts")
    assert_equal "Ana", @user.reload.name
    assert_equal "5545988115410", @user.phone
  end

  test "an invalid profile re-renders with a 422" do
    patch onboarding_step_url("profile"), params: { user: { name: "", country_code: "55", phone_national: "" } }
    assert_response :unprocessable_entity
  end

  test "accounts step will not advance with zero accounts" do
    complete_profile
    patch onboarding_step_url("accounts")
    assert_redirected_to onboarding_step_url("accounts")
    assert_not @user.reload.onboarded?
  end

  test "accounts step advances once there is at least one account" do
    complete_profile
    @user.bank_accounts.create!(institution: @nubank)
    patch onboarding_step_url("accounts")
    assert_redirected_to onboarding_step_url("cards")
  end

  test "cards step finishes onboarding and lands on the dashboard" do
    complete_profile
    @user.bank_accounts.create!(institution: @nubank)
    patch onboarding_step_url("cards")
    assert_redirected_to dashboard_url
    assert @user.reload.onboarded?
  end

  test "the profile step shows the WhatsApp activation prompt once the phone is set" do
    complete_profile
    get onboarding_step_url("profile")
    assert_response :success

    code = @user.reload.whatsapp_verification_code
    assert_match(/\AAZUL-[A-Z0-9]{4}\z/, code)
    assert_includes response.body, code
    assert_includes response.body, I18n.t("whatsapp.activation.subtitle", locale: :"pt-BR")
  end

  test "the profile step hides the activation prompt before the phone is set" do
    # The confirmed fixture starts with no name/phone, so the profile step resolves here.
    get onboarding_step_url("profile")
    assert_response :success
    assert_not_includes response.body, I18n.t("whatsapp.activation.subtitle", locale: :"pt-BR")
    assert_nil @user.reload.whatsapp_verification_code
  end

  test "already-onboarded users are redirected out of the wizard" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    get onboarding_url
    assert_redirected_to dashboard_url
  end

  test "deleting the only account after advancing blocks finishing" do
    complete_profile
    account = @user.bank_accounts.create!(institution: @nubank)   # advances to the cards step
    account.destroy                                                # …then the account is removed
    patch onboarding_step_url("cards")
    assert_redirected_to onboarding_step_url("accounts")
    assert_not @user.reload.onboarded?
  end

  test "a fresh user cannot PATCH straight to finishing the wizard" do
    patch onboarding_step_url("cards")                             # no profile, no accounts
    assert_redirected_to onboarding_step_url("profile")
    assert_not @user.reload.onboarded?
  end
end
