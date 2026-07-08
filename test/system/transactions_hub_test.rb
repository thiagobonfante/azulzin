require "application_system_test_case"

# Drives the real add → assign → delete flow in a browser, so the Stimulus auto-select and the
# Turbo Stream re-render (which unit tests can't exercise) are actually verified.
class TransactionsHubTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier   # dom_id(...) for asserting the row frame is gone

  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    inst = Institution.find_by(code: "260")
    @account = @user.account.bank_accounts.create!(institution: inst, nickname: "Conta Nubank")
    @card    = @user.account.credit_cards.create!(institution: inst, nickname: "Cartão Nubank",
                                          bill_due_day: 10, closing_offset_days: 7)
    @user.account.categories.create!(name: "Viagem")

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
    assert_equal @account, @user.account.transactions.order(:id).last.bank_account

    # Exactly one ledger — the id collision that duplicated it is gone (issue 2).
    assert_selector "input[type='search']", count: 1
    assert_no_text I18n.t("transactions.ledger.empty")   # empty state replaced (issue 6)

    # The row opens into an editable form again (issue 5), so delete is reachable. Deleting goes
    # through our on-brand confirm modal — a real DOM <dialog> we can drive with actual clicks,
    # unlike the native confirm() headless Chrome never surfaces to Capybara.
    find("#ledger_list a", text: "Mercado").click
    assert_button I18n.t("transactions.row.save")
    txn = @user.account.transactions.order(:id).last
    click_link I18n.t("transactions.row.reverse")   # "Apagar"

    # The modal must be actually VISIBLE — Capybara will happily click a transparent overlay, so
    # a daisyUI/CSS regression that leaves the box at opacity:0 would otherwise pass unnoticed.
    assert_selector "dialog.modal[open]"
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('dialog.modal .modal-box')).opacity"),
                 "the confirm modal must be visible, not a transparent overlay"

    within "dialog.modal[open]" do                   # our modal, not the native dialog
      assert_text I18n.t("transactions.row.confirm_discard")
      click_button I18n.t("shared.confirm")
    end

    # Confirm streamed the removal: the row frame is gone and the record is soft-deleted
    # (doc 05 §2.6 — in-app delete keeps the row, restorable via console).
    assert_no_selector "##{dom_id(txn, :row)}"
    assert txn.reload.soft_deleted?
  end

  test "the confirm modal Cancel button aborts the delete — row and record stay put" do
    txn = @user.account.transactions.create!(bank_account: @account, category: @user.account.categories.first,
                                     direction: "expense", status: "posted", amount_cents: 3_100,
                                     occurred_on: Date.current, billing_month: Date.current.beginning_of_month,
                                     merchant: "Farmácia")
    visit transactions_path

    find("#ledger_list a", text: "Farmácia").click
    click_link I18n.t("transactions.row.reverse")

    within "dialog.modal[open]" do
      click_button I18n.t("shared.cancel")
    end

    assert_no_selector "dialog.modal[open]"          # modal closed
    assert_selector "##{dom_id(txn, :row)}"          # the row is still there
    assert_equal "posted", txn.reload.status         # nothing was reversed
  end

  test "switching to Categories keeps the toggle in place and hides the search (issue 6a)" do
    @user.account.transactions.create!(bank_account: @account, category: @user.account.categories.first,
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
