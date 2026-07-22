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

  def add_account = @account ||= @user.account.bank_accounts.create!(institution: @nubank)

  def add_income
    add_account
    @user.account.incomes.create!(bank_account: @account, name: "salário", amount_cents: 450_000,
                          schedule_kind: "fixed_day", schedule_day: 5)
  end

  test "accounts step advances to the incomes step once there is at least one account" do
    complete_profile
    add_account
    patch onboarding_step_url("accounts")
    assert_redirected_to onboarding_step_url("incomes")
  end

  test "the incomes and cards steps render their forms" do
    complete_profile
    add_account
    get onboarding_step_url("incomes")
    assert_response :success
    assert_select "form#income_form"
    add_income
    get onboarding_step_url("cards")
    assert_response :success
    assert_select "form#credit_card_form"
  end

  test "incomes step will not advance with zero incomes" do
    complete_profile
    add_account
    patch onboarding_step_url("incomes")
    assert_redirected_to onboarding_step_url("incomes")
    assert_not @user.reload.onboarded?
  end

  test "incomes step advances to cards once there is at least one income" do
    complete_profile
    add_income
    patch onboarding_step_url("incomes")
    assert_redirected_to onboarding_step_url("cards")
  end

  test "PATCH onboarding/cards with zero incomes redirects back to the incomes step" do
    complete_profile
    add_account # account but no income → resume is incomes; cards is ahead
    patch onboarding_step_url("cards")
    assert_redirected_to onboarding_step_url("incomes")
    assert_not @user.reload.onboarded?
  end

  test "GET onboarding/cards with zero incomes deep-links back to incomes" do
    complete_profile
    add_account
    get onboarding_step_url("cards")
    assert_redirected_to onboarding_step_url("incomes")
  end

  test "cards step finishes onboarding once profile, accounts and incomes are done" do
    complete_profile
    add_income
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
    account = @user.account.bank_accounts.create!(institution: @nubank)   # advances to the cards step
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

  # ── Phase 5: skip affordance (D5) + owner account-name prompt (decision #4) ──

  def skip_label = I18n.t("onboarding.skip_to_app", locale: :"pt-BR")

  # A fresh owner with an empty account may skip everything past profile; recording
  # transactions/commitments stays blocked until an instrument exists (require_instrument).
  test "a fresh owner with an empty account can skip to the app from the accounts step" do
    complete_profile
    get onboarding_step_url("accounts")
    assert_response :success
    assert_includes response.body, skip_label

    patch onboarding_skip_url
    assert_redirected_to dashboard_url
    assert @user.reload.onboarded?
  end

  test "an invited member of a stocked account can skip to the app without duplicating categories" do
    @user.update!(name: "Owner", phone: "5511900000000", onboarded_at: Time.current)
    add_income
    @user.onboard!                                                 # owner seeds the 13 categories
    assert_equal 13, @user.account.categories.kept.count

    member = User.create!(email_address: "bia@example.com", password: "password123", name: "Bia", phone: "5511988887777")
    @user.account.memberships.create!(user: member, role: "member")
    sign_out
    sign_in_as(member)

    get onboarding_step_url("accounts")                            # resume is cards; skip shows here
    assert_response :success
    assert_includes response.body, skip_label

    patch onboarding_skip_url
    assert_redirected_to dashboard_url
    assert member.reload.onboarded?
    assert_equal 13, @user.account.categories.kept.count, "no duplicate categories (call-site guard)"
  end

  test "a member with an incomplete profile cannot skip (bounces to profile, stays not onboarded)" do
    @user.update!(name: "Owner", phone: "5511900000000", onboarded_at: Time.current)
    add_income
    member = User.create!(email_address: "c@example.com", password: "password123")   # no name/phone
    @user.account.memberships.create!(user: member, role: "member")
    sign_out
    sign_in_as(member)
    patch onboarding_skip_url
    assert_redirected_to onboarding_step_url("profile")
    assert_not member.reload.onboarded?
  end

  test "skipping still finishes when the only account was soft-deleted after advancing" do
    complete_profile
    add_account.soft_delete!(by: @user)                           # the only account is soft-deleted
    patch onboarding_skip_url
    assert_redirected_to dashboard_url
    assert @user.reload.onboarded?
  end

  test "the owner names the shared account on the profile step" do
    patch onboarding_step_url("profile"),
      params: { user: { name: "Thiago", country_code: "55", phone_national: "11912345678", account_name: "Família Bonfante" } }
    assert_redirected_to onboarding_step_url("accounts")
    assert_equal "Família Bonfante", @user.account.reload.name
  end

  test "an invited member's account_name submission is ignored (not the owner)" do
    @user.update!(name: "Owner", onboarded_at: Time.current)
    original = @user.account.name
    member = User.create!(email_address: "d@example.com", password: "password123")
    @user.account.memberships.create!(user: member, role: "member")
    sign_out
    sign_in_as(member)
    patch onboarding_step_url("profile"),
      params: { user: { name: "Bia", country_code: "55", phone_national: "11988887777", account_name: "Hijack" } }
    assert_equal original, @user.account.reload.name
  end
end
