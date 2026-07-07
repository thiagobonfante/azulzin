require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst    = Institution.find_by(code: "260")
    @account = @user.account.bank_accounts.create!(institution: @inst, nickname: "Salário")
    @card    = @user.account.credit_cards.create!(institution: @inst, nickname: "Roxinho")
  end

  def pending_txn(**attrs)
    @user.account.transactions.create!({ amount_cents: 1_323, occurred_on: Date.current, status: "pending_review" }.merge(attrs))
  end

  test "a manual add without an instrument is rejected — never silently parked in the tray" do
    @user.account.credit_cards.create!(institution: @inst, nickname: "Segundo") # two cards: no auto-assign
    assert_no_difference -> { @user.account.transactions.count } do
      post transactions_url(kind: "expense"), params: {
        transaction: { amount_reais: "100,00", merchant: "test", occurred_on: Date.current.to_s,
                       category_id: "", payment_method: "credito" },
        instrument: ""
      }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.models.transaction.instrument_required"), response.body
  end

  test "A pagar groups: open debit rows inline, card and paid occurrences fold into details" do
    month = Date.current.beginning_of_month
    open_debit = @user.account.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                           amount_cents: 100_000, schedule_day: 5, starts_on: month)
    paid_debit = @user.account.commitments.create!(bank_account: @account, name: "pensão", kind: "fixed",
                                           amount_cents: 50_000, schedule_day: 5, starts_on: month)
    Commitments::MarkPaid.call(paid_debit, month)
    @user.account.commitments.create!(credit_card: @card, name: "Netflix", kind: "subscription",
                              amount_cents: 5_500, schedule_kind: "fixed_day", starts_on: month)

    get transactions_url(month: month.strftime("%Y-%m"))
    assert_response :success
    assert_select "#a_pagar" do
      assert_select "details summary", text: /no cartão/
      assert_select "details summary", text: /paga/
    end
    assert_match open_debit.name, response.body
  end

  test "index requires a completed onboarding" do
    @user.update!(onboarded_at: nil)
    get transactions_url
    assert_redirected_to onboarding_url
  end

  test "index lists the user's pending + posted-unassigned rows, scoped to the user" do
    mine  = pending_txn
    other = User.create!(email_address: "other@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    theirs = other.account.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")

    get transactions_url
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(mine)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(theirs)}", count: 0
  end

  test "saving the tray card charges the expense to the chosen account" do
    txn = pending_txn
    patch transaction_url(txn), params: { transaction: { amount_reais: "13,23" },
                                          instrument: "bank_account-#{@account.id}" }
    assert_redirected_to transactions_path
    assert_equal @account, txn.reload.bank_account
    assert_nil txn.credit_card
  end

  test "saving the tray card with a blank instrument clears any assignment" do
    txn = pending_txn(bank_account: @account)
    patch transaction_url(txn), params: { transaction: { amount_reais: "13,23" }, instrument: "" }
    assert_nil txn.reload.bank_account
    assert_nil txn.credit_card
  end

  test "a ledger edit without an instrument field leaves the assignment alone" do
    txn = pending_txn(status: "posted", bank_account: @account)
    patch transaction_url(txn), params: { from: "ledger", transaction: { amount_reais: "13,23", merchant: "Feira" } }
    assert_equal @account, txn.reload.bank_account
  end

  test "confirm posts a pending transaction" do
    txn = pending_txn
    patch confirm_transaction_url(txn)
    assert txn.reload.posted?
    assert txn.confirmed_at.present?
  end

  test "update edits the amount and merchant" do
    txn = pending_txn
    patch transaction_url(txn), params: { transaction: { amount_reais: "50,00", merchant: "Padaria" } }
    txn.reload
    assert_equal 5_000, txn.amount_cents
    assert_equal "Padaria", txn.merchant
  end

  test "destroy soft-deletes a posted transaction" do
    txn = pending_txn(status: "posted", bank_account: @account)
    delete transaction_url(txn)
    assert txn.reload.soft_deleted?
    assert txn.posted?, "status is untouched — reverse!/rejected stays a WhatsApp-pipeline concern"
  end

  test "cannot touch another user's transaction" do
    other = User.create!(email_address: "other2@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    theirs = other.account.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")
    patch confirm_transaction_url(theirs)
    assert_response :not_found
    assert theirs.reload.pending_review?
  end

  test "a tray save with an instrument answers a turbo stream" do
    txn = pending_txn
    patch transaction_url(txn), params: { transaction: { amount_reais: "13,23" },
                                          instrument: "credit_card-#{@card.id}" }, as: :turbo_stream
    assert_response :success
    assert_equal @card, txn.reload.credit_card
  end

  test "confirm saves the review form's edits — description and account post together" do
    txn = pending_txn(merchant: "52.551.773 GABRIELLY")
    patch confirm_transaction_url(txn), params: {
      transaction: { amount_reais: "80,00", merchant: "Gabrielly", payment_method: "pix" },
      instrument: "bank_account-#{@account.id}"
    }, as: :turbo_stream
    txn.reload
    assert txn.posted?
    assert_equal "Gabrielly", txn.merchant
    assert_equal 8_000, txn.amount_cents
    assert_equal "pix", txn.payment_method
    assert_equal @account, txn.bank_account
  end

  test "confirm with an invalid edit re-renders the card with errors and stays pending" do
    txn = pending_txn
    patch confirm_transaction_url(txn), params: { transaction: { amount_reais: "abc" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert txn.reload.pending_review?
  end

  test "the tray card is ONE form: avatar picker, extracted method active, no Definir button" do
    txn = pending_txn(merchant: "Gabrielly", payment_method: "pix",
                      source: "whatsapp_receipt", direction: "expense")
    get transactions_url
    assert_select "##{ActionView::RecordIdentifier.dom_id(txn)}" do
      assert_select "form[action=?]", transaction_path(txn), count: 1
      assert_select "form", count: 1                                       # the split Definir form is gone
      assert_select "button[data-method='pix'][data-active='true']"        # pix pre-selected from extraction
      assert_select "[data-entry-instrument-target='option'][data-value='bank_account-#{@account.id}']"
      assert_select "input[type=submit][formaction=?]", confirm_transaction_path(txn)
    end
  end

  # ── Phase 1 hub VERIFY ───────────────────────────────────────────────────

  test "month resolver: garbage/out-of-range params behave" do
    get transactions_url(month: "2026-13"); assert_response :success           # invalid → today
    get transactions_url(month: "garbage"); assert_response :success           # invalid → today
    high = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month >> 12
    get transactions_url(month: "2050-01")                                     # out of range → clamp
    assert_redirected_to transactions_path(month: high.strftime("%Y-%m"))
  end

  test "month default is the São Paulo month, not UTC's, near midnight" do
    travel_to Time.utc(2026, 8, 1, 1, 0) do # 22:00 on Jul 31 in São Paulo
      get transactions_url
      assert_includes @response.body, "julho de 2026"
    end
  end

  test "a d10/f7 card expense lands on the August fatura and August ledger" do
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    txn = @user.account.transactions.create!(amount_cents: 5_000, occurred_on: Date.new(2026, 7, 4),
                                     status: "posted", direction: "expense", credit_card: @card)
    assert_equal Date.new(2026, 8, 1), txn.billing_month
    get transactions_url(month: "2026-08")
    assert_select "##{ActionView::RecordIdentifier.dom_id(txn, :row)}"
    get transactions_url(month: "2026-07")
    assert_select "##{ActionView::RecordIdentifier.dom_id(txn, :row)}", count: 0
  end

  test "row edit Fatura select sets the manual flag; a later occurred_on edit leaves it" do
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    txn = @user.account.transactions.create!(amount_cents: 5_000, occurred_on: Date.new(2026, 7, 4),
                                     status: "posted", direction: "expense", credit_card: @card)
    # move to setembro
    patch transaction_url(txn), params: { from: "ledger", month: "2026-08",
      transaction: { amount_reais: "50,00", merchant: "", occurred_on: "2026-07-04", billing_month: "2026-09-01" } }
    txn.reload
    assert_equal Date.new(2026, 9, 1), txn.billing_month
    assert txn.billing_month_manual?
    # editing occurred_on must NOT clobber the manual move
    patch transaction_url(txn), params: { from: "ledger", month: "2026-09",
      transaction: { amount_reais: "50,00", merchant: "", occurred_on: "2026-06-01", billing_month: "2026-09-01" } }
    assert_equal Date.new(2026, 9, 1), txn.reload.billing_month
    assert txn.billing_month_manual?
  end

  test "confirming a pending row travels it into the viewed month's ledger" do
    txn = pending_txn(bank_account: @account, occurred_on: Date.new(2026, 7, 10))
    patch confirm_transaction_url(txn), params: { month: "2026-07" }, as: :turbo_stream
    assert_response :success
    assert txn.reload.posted?
    assert_includes @response.body, ActionView::RecordIdentifier.dom_id(txn, :row) # prepended into ledger
    assert_includes @response.body, "hero"                                          # figures re-rendered
  end

  test "deleting a posted row never writes balance_cents / current_bill_cents (pure record)" do
    @account.update!(balance_cents: 100_000)
    @card.update!(current_bill_cents: 50_000)
    txn = @user.account.transactions.create!(amount_cents: 5_000, occurred_on: Date.current,
                                     status: "posted", direction: "expense", bank_account: @account)
    delete transaction_url(txn), params: { from: "ledger", month: Date.current.strftime("%Y-%m") }, as: :turbo_stream
    assert txn.reload.soft_deleted?
    assert_equal 100_000, @account.reload.balance_cents
    assert_equal 50_000, @card.reload.current_bill_cents
    assert_equal 0, @user.account.transactions.spend.count   # spend is .kept — the deleted row drops out
  end

  test "confirming a parked installment stub creates the plan and supersedes the stub" do
    @card.update!(bill_due_day: 10, closing_offset_days: 10)
    stub = pending_txn(amount_cents: 500_000, merchant: "celular", occurred_on: Date.new(2026, 7, 3),
                       billing_month: Date.new(2026, 7, 1), credit_card: @card,
                       extraction: { "installments_count" => 10, "installment_total_raw" => "5000" })
    assert_difference -> { @user.account.commitments.installment.count }, 1 do
      patch confirm_transaction_url(stub), params: { month: "2026-07" }, as: :turbo_stream
    end
    assert_equal "superseded", stub.reload.status
    c = @user.account.commitments.installment.last
    assert_equal 10, c.installments_count
    assert_equal 0, c.payments.count, "parcels are computed occurrences, not eager posted rows"

    # A second confirm must NOT re-expand (the stub is already superseded).
    assert_no_difference -> { @user.account.commitments.installment.count } do
      patch confirm_transaction_url(stub), params: { month: "2026-07" }, as: :turbo_stream
    end
  end

  test "a ledger month with 250 rows shows the show-more link; show_all renders them" do
    month = Date.current.beginning_of_month
    250.times do
      @user.account.transactions.create!(bank_account: @account, direction: "expense", status: "posted",
                                 amount_cents: 100, occurred_on: Date.current, billing_month: month)
    end
    get transactions_url(month: month.strftime("%Y-%m"))
    assert_select "a", text: I18n.t("transactions.ledger.show_more", locale: :"pt-BR")
    get transactions_url(month: month.strftime("%Y-%m"), show_all: 1)
    assert_response :success
  end

  test "create adds a posted expense and re-renders the ledger frame (not the h2 anchor)" do
    assert_difference -> { @user.account.transactions.spend.count }, 1 do
      post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
           params: { transaction: { amount_reais: "12,00", merchant: "Feira", occurred_on: Date.current.to_s },
                     instrument: "bank_account-#{@account.id}" }
    end
    txn = @user.account.transactions.order(:id).last
    assert_equal 1_200, txn.amount_cents
    assert_equal @account, txn.bank_account
    # Guards the id collision that duplicated the list: the stream targets the frame, not #ledger.
    assert_select "turbo-stream[action='replace'][target='movements_ledger']"
    assert_select "turbo-stream[action='replace'][target='ledger']", count: 0
  end

  test "manual create auto-assigns the lone card for crédito without an instrument token (issue 3)" do
    post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "30,00", occurred_on: Date.current.to_s, payment_method: "credito" } }
    txn = @user.account.transactions.order(:id).last
    assert_equal @card, txn.credit_card
    assert_nil txn.bank_account
    assert txn.assigned?, "should not land unassigned in the review tray"
  end

  test "manual create auto-assigns the lone account for pix without an instrument token (issue 3)" do
    post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "30,00", occurred_on: Date.current.to_s, payment_method: "pix" } }
    txn = @user.account.transactions.order(:id).last
    assert_equal @account, txn.bank_account
    assert_nil txn.credit_card
  end

  test "an entry that lands on another month shows a toast pointing there (issue 4)" do
    post transactions_url(kind: "expense", month: "2026-07"), as: :turbo_stream,
         params: { transaction: { amount_reais: "12,00", occurred_on: "2026-08-15", payment_method: "pix" },
                   instrument: "bank_account-#{@account.id}" }
    assert_select "turbo-stream[action='prepend'][target='toasts']"
  end

  test "create stores the payment_method chosen on the form" do
    post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "20,00", occurred_on: Date.current.to_s, payment_method: "credito" },
                   instrument: "credit_card-#{@card.id}" }
    assert_equal "credito", @user.account.transactions.order(:id).last.payment_method
  end

  test "new expense form renders the payment-method control and avatar instrument options" do
    get new_transaction_url(kind: "expense", month: Date.current.strftime("%Y-%m"))
    assert_response :success
    assert_select "[data-controller~='entry-instrument']"
    assert_select "[data-controller~='category-suggest']"
    assert_select "button[data-method='credito']"
    assert_select "button[data-method='pix']"
    assert_select "[data-entry-instrument-target='option'][data-value='credit_card-#{@card.id}']"
    assert_select "[data-entry-instrument-target='option'][data-value='bank_account-#{@account.id}']"
  end

  test "new income form offers accounts only — no cards, no payment method (item 4)" do
    get new_transaction_url(kind: "income", month: Date.current.strftime("%Y-%m"))
    assert_response :success
    assert_select "button[data-method]", count: 0
    assert_select "[data-entry-instrument-target='option'][data-type='credit_card']", count: 0
    assert_select "[data-entry-instrument-target='option'][data-value='bank_account-#{@account.id}']"
  end

  test "index renders the spend-allocation chart when the month has spending (item 1)" do
    cat = @user.account.categories.create!(name: "Mercado", color: "#22C55E", icon: "cart")
    @user.account.transactions.create!(bank_account: @account, category: cat, direction: "expense", status: "posted",
                               amount_cents: 100, occurred_on: Date.current, billing_month: Date.current.beginning_of_month)
    get transactions_url
    assert_response :success
    assert_select "[role='img'][aria-label=?]", I18n.t("transactions.hero.allocation_label", locale: :"pt-BR")
  end

  test "the transfer tab is hidden with a single account and shown with two (R5)" do
    get new_transaction_url(kind: "expense")
    assert_select "a[href*='kind=transfer']", count: 0

    @user.account.bank_accounts.create!(institution: @inst, nickname: "Segunda")
    get new_transaction_url(kind: "expense")
    assert_select "a[href*='kind=transfer']"
  end

  test "a future month renders the editable ledger like the current month (parity)" do
    get transactions_url(month: (Date.current.beginning_of_month >> 2).strftime("%Y-%m"))
    assert_response :success
    assert_select "turbo-frame#movements_ledger"   # editable ledger, not the read-only Previsto
    assert_select "a[href*='transactions/new']"     # the Adicionar affordance
  end

  test "the add form on a future month defaults the date into that month" do
    future = Date.current.beginning_of_month >> 2
    get new_transaction_url(kind: "expense", month: future.strftime("%Y-%m"))
    assert_response :success
    assert_select "input[name='transaction[occurred_on]'][value=?]", future.to_s
  end

  test "a future-dated income posts to that month (bonus use case)" do
    future = Date.current.beginning_of_month >> 1
    post transactions_url(kind: "income", month: future.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "2000,00", occurred_on: future.to_s },
                   instrument: "bank_account-#{@account.id}" }
    txn = @user.account.transactions.order(:id).last
    assert_equal "income", txn.direction
    assert_equal future, txn.billing_month
    assert_predicate txn, :posted?
  end

  # ── No instruments (onboarding skipped): creation is blocked until an account/card exists ──

  def remove_instruments
    @account.soft_delete!(by: @user)
    @card.soft_delete!(by: @user)
  end

  test "new with no instruments renders the create-an-account-first prompt instead of the form" do
    remove_instruments
    get new_transaction_url(kind: "expense")
    assert_response :success
    assert_includes response.body, I18n.t("shared.needs_instrument.title", locale: :"pt-BR")
    assert_select "form", false
  end

  test "create with no instruments is blocked" do
    remove_instruments
    assert_no_difference -> { @user.account.transactions.count } do
      post transactions_url(kind: "expense"), params: {
        transaction: { amount_reais: "100,00", merchant: "test", occurred_on: Date.current.to_s,
                       category_id: "", payment_method: "pix" },
        instrument: ""
      }, as: :turbo_stream
    end
    assert_includes response.body, I18n.t("shared.needs_instrument.title", locale: :"pt-BR")
  end

  # ── Receipts (up-tier F5): manual upload, scoped serving, display ──

  def posted_with_receipt(fixture: "receipt.jpg", content_type: "image/jpeg")
    txn = @user.account.transactions.create!(amount_cents: 1_000, occurred_on: Date.current,
                                             status: "posted", bank_account: @account)
    txn.receipt.attach(io: File.open(file_fixture(fixture)), filename: fixture, content_type: content_type)
    txn
  end

  test "manual add with a receipt attaches it and the ledger row shows the paperclip" do
    post transactions_url(kind: "expense"), params: {
      transaction: { amount_reais: "50,00", merchant: "padaria", occurred_on: Date.current.to_s,
                     category_id: "", payment_method: "pix",
                     receipt: fixture_file_upload("receipt.jpg", "image/jpeg") },
      instrument: "bank_account-#{@account.id}"
    }
    assert_redirected_to transactions_path
    txn = @user.account.transactions.sole
    assert txn.receipt.attached?

    get transactions_url
    assert_select "[title=?]", I18n.t("transactions.row.has_receipt")
  end

  test "an .exe renamed .jpg is rejected by magic bytes and nothing is created" do
    assert_no_difference -> { @user.account.transactions.count } do
      post transactions_url(kind: "expense"), params: {
        transaction: { amount_reais: "50,00", merchant: "padaria", occurred_on: Date.current.to_s,
                       category_id: "", payment_method: "pix",
                       receipt: fixture_file_upload("receipt_fake.jpg", "image/jpeg") },
        instrument: "bank_account-#{@account.id}"
      }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.models.transaction.attributes.receipt.unsupported_type"), response.body
  end

  test "editing without picking a new file keeps the existing receipt" do
    txn = posted_with_receipt
    patch transaction_url(txn), params: { transaction: { amount_reais: "13,23", receipt: "" } }
    assert txn.reload.receipt.attached?, "a blank file field must never detach the current receipt"
  end

  test "serves the receipt bytes and the thumb variant to a member of the account" do
    txn = posted_with_receipt
    get receipt_transaction_url(txn)
    assert_response :success
    assert_equal "image/jpeg", response.media_type

    get receipt_transaction_url(txn, size: "thumb")
    assert_response :success
    assert_match(/\Aimage\//, response.media_type)
  end

  test "a member of another account cannot fetch the receipt (404)" do
    other = User.create!(email_address: "other-receipt@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    theirs = other.account.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "posted")
    theirs.receipt.attach(io: File.open(file_fixture("receipt.jpg")), filename: "r.jpg", content_type: "image/jpeg")

    get receipt_transaction_url(theirs)
    assert_response :not_found
  end

  test "a transaction without a receipt 404s on the receipt path" do
    txn = @user.account.transactions.create!(amount_cents: 500, occurred_on: Date.current,
                                             status: "posted", bank_account: @account)
    get receipt_transaction_url(txn)
    assert_response :not_found
  end

  test "the edit row shows a thumbnail for an image receipt" do
    txn = posted_with_receipt
    get edit_transaction_url(txn)
    assert_response :success
    assert_select "img[src=?]", receipt_transaction_path(txn, size: "thumb")
  end

  test "a PDF receipt shows the view link instead of a thumbnail" do
    txn = posted_with_receipt(fixture: "receipt.pdf", content_type: "application/pdf")
    get edit_transaction_url(txn)
    assert_response :success
    assert_select "a[href=?]", receipt_transaction_path(txn),
                  text: I18n.t("transactions.row.view_receipt")
    assert_select "img[src=?]", receipt_transaction_path(txn, size: "thumb"), count: 0
  end
end
