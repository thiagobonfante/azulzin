require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    sign_in_as(@user)
  end

  test "requires authentication" do
    sign_out
    get dashboard_url
    assert_redirected_to new_session_url
  end

  test "an un-onboarded user is sent to the wizard" do
    get dashboard_url
    assert_redirected_to onboarding_url
  end

  test "renders totals for an onboarded user" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    nubank = Institution.find_by(code: "260")
    @user.account.bank_accounts.create!(institution: nubank, balance_cents: 150000)
    @user.account.credit_cards.create!(institution: nubank, credit_limit_cents: 800000, current_bill_cents: 200000)

    get dashboard_url
    assert_response :success
    assert_select "h1"
  end

  test "an onboarded user hitting the app root is redirected to the dashboard" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    get root_url
    assert_redirected_to dashboard_url
  end

  test "an unverified user sees the WhatsApp activation prompt and a code is persisted" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    assert_nil @user.whatsapp_verification_code

    get dashboard_url
    assert_response :success

    code = @user.reload.whatsapp_verification_code
    assert_match(/\AAZUL-[A-Z0-9]{4}\z/, code)
    assert_includes response.body, code
    assert_includes response.body, I18n.t("whatsapp.activation.subtitle", locale: :"pt-BR")
  end

  test "a verified user does not see the WhatsApp activation prompt" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current,
                  phone_verified_at: Time.current)
    get dashboard_url
    assert_response :success
    assert_not_includes response.body, I18n.t("whatsapp.activation.subtitle", locale: :"pt-BR")
    assert_nil @user.reload.whatsapp_verification_code
  end

  test "total available credit ignores cards with a bill but no limit" do
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    nubank = Institution.find_by(code: "260")
    @user.account.credit_cards.create!(institution: nubank, credit_limit_cents: 100000, current_bill_cents: 20000) # avail 800,00
    @user.account.credit_cards.create!(institution: nubank, current_bill_cents: 50000)                             # no limit
    get dashboard_url
    assert_response :success
    # Available = 100000 − 20000 only. The limitless card's 500,00 bill must NOT reduce it
    # (the bug summed all bills against the limit total, yielding 300,00).
    assert_match "800,00", response.body
    assert_no_match(/300,00/, response.body)
  end
end
