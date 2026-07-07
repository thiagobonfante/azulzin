require "test_helper"

class ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(onboarded_at: Time.current)
    sign_in_as(@user)
    inst  = Institution.find_by(code: "260")
    @bank = @user.account.bank_accounts.create!(institution: inst, nickname: "Corrente")
  end

  def txn(account: @user.account, bank: @bank, **attrs)
    account.transactions.create!({ amount_cents: 1_000, occurred_on: Date.current,
                                   status: "posted", direction: "expense",
                                   bank_account: bank }.merge(attrs))
  end

  test "authentication required for the form and the download" do
    sign_out
    get new_export_url
    assert_redirected_to new_session_url
    get exports_url, params: { preset: "all", format: "csv" }
    assert_redirected_to new_session_url
  end

  test "the form renders with the presets and xlsx as the first format" do
    get new_export_url
    assert_response :success
    assert_select "form[action=?]", exports_path do
      assert_select "select[name=format] option:first-of-type[value=xlsx]"
      assert_select "input[type=radio][name=preset]", count: 5
      assert_select "input[type=date][name=from]"
    end
  end

  test "csv download is account-scoped and excludes soft-deleted and rejected rows" do
    txn(merchant: "minha padaria")
    txn(merchant: "rejeitada", status: "rejected")
    txn(merchant: "apagada").soft_delete!(by: @user)
    other_bank = accounts(:english).bank_accounts.create!(institution: Institution.find_by(code: "260"))
    txn(account: accounts(:english), bank: other_bank, merchant: "alheia")

    get exports_url, params: { preset: "all", format: "csv" }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"],
                    "azulzin-extrato-#{Date.current.strftime("%Y-%m")}.csv"
    assert_includes response.body, "minha padaria"
    assert_not_includes response.body, "rejeitada"
    assert_not_includes response.body, "apagada"
    assert_not_includes response.body, "alheia"
  end

  test "xlsx is the default format, including for an unknown format param" do
    txn(merchant: "qualquer")
    get exports_url, params: { preset: "current_month" }
    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type
    assert response.body.start_with?("PK"), "xlsx must be a zip container"
    assert_includes response.headers["Content-Disposition"], ".xlsx"

    get exports_url, params: { preset: "current_month", format: "evil" }
    assert_equal Mime[:xlsx].to_s, response.media_type
  end

  test "pdf downloads as a rendered document" do
    txn(merchant: "padaria")
    get exports_url, params: { preset: "current_month", format: "pdf" }
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
  end

  test "custom preset bounds the export by occurred_on; garbage dates do not error" do
    txn(merchant: "dentro", occurred_on: Date.new(2026, 7, 10))
    txn(merchant: "fora",   occurred_on: Date.new(2026, 5, 10))
    get exports_url, params: { preset: "custom", from: "2026-07-01", to: "2026-07-31", format: "csv" }
    assert_includes response.body, "dentro"
    assert_not_includes response.body, "fora"

    get exports_url, params: { preset: "custom", from: "not-a-date", to: "31/07", format: "csv" }
    assert_response :success
  end

  test "a missing or unknown preset falls back to the current month" do
    txn(merchant: "deste mês")
    txn(merchant: "do passado", occurred_on: Date.current << 3)
    get exports_url, params: { format: "csv" }
    assert_includes response.body, "deste mês"
    assert_not_includes response.body, "do passado"
  end
end
