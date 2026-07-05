require "application_system_test_case"

# Drives the real add → assign → delete flow in a browser, so the Stimulus auto-select and the
# Turbo Stream re-render (which unit tests can't exercise) are actually verified.
class TransactionsHubTest < ApplicationSystemTestCase
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    inst = Institution.find_by(code: "260")
    @account = @user.bank_accounts.create!(institution: inst, nickname: "Conta Nubank")
    @card    = @user.credit_cards.create!(institution: inst, nickname: "Cartão Nubank",
                                          bill_due_day: 10, closing_offset_days: 7)
    @user.categories.create!(name: "Viagem")

    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password123"
    click_button I18n.t("sessions.new.submit")
    # Wait for the post-login redirect so the session cookie is set before we navigate on.
    assert_text I18n.t("dashboard.greeting", name: "Ana")
  end

  test "pix add auto-assigns the account, renders exactly one ledger, and deletes cleanly" do
    visit transactions_path
    find("a[href*='transactions/new']").click   # the ledger's "Adicionar"

    within "#new_entry" do
      fill_in I18n.t("transactions.row.amount"), with: "12,00"
      fill_in I18n.t("transactions.row.merchant"), with: "Mercado"
      find("button[data-method='pix']").click
      # The lone account auto-selects for pix.
      assert_selector "[data-entry-instrument-target='display']", text: "Conta Nubank"
      click_button I18n.t("transactions.new.submit")
    end

    # The row is in the ledger, not the review tray — it came out assigned (issue 3).
    assert_text "Mercado"
    assert_no_selector "#pending_tray"
    assert_equal @account, @user.transactions.order(:id).last.bank_account

    # Exactly one ledger — the id collision that duplicated it is gone (issue 2).
    assert_selector "input[type='search']", count: 1
    assert_no_text I18n.t("transactions.ledger.empty")   # empty state replaced (issue 6)

    # The row opens into an editable form again — the collision that made rows inert is gone, so
    # delete (the "Apagar" button) is reachable (issue 5). The destroy itself, behind a native
    # confirm that headless Chrome won't surface to Capybara, is covered in the controller test.
    find("#ledger_list a", text: "Mercado").click
    assert_button I18n.t("transactions.row.reverse")
    assert_button I18n.t("transactions.row.save")
  end

  test "switching to Categories keeps the toggle in place and hides the search (issue 6a)" do
    @user.transactions.create!(bank_account: @account, category: @user.categories.first,
                               direction: "expense", status: "posted", amount_cents: 2_400,
                               occurred_on: Date.current, billing_month: Date.current.beginning_of_month,
                               merchant: "Mercado")
    visit transactions_path

    toggle = find("button[data-view='category']")
    x_before = toggle.native.location.x
    toggle.click

    assert_no_selector "[data-ledger-target='searchBox']", visible: true
    assert_in_delta x_before, find("button[data-view='category']").native.location.x, 2
  end
end
