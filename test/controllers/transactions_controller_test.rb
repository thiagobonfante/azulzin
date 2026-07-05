require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst    = Institution.find_by(code: "260")
    @account = @user.bank_accounts.create!(institution: @inst, nickname: "Salário")
    @card    = @user.credit_cards.create!(institution: @inst, nickname: "Roxinho")
  end

  def pending_txn(**attrs)
    @user.transactions.create!({ amount_cents: 1_323, occurred_on: Date.current, status: "pending_review" }.merge(attrs))
  end

  test "index requires a completed onboarding" do
    @user.update!(onboarded_at: nil)
    get transactions_url
    assert_redirected_to onboarding_url
  end

  test "index lists the user's pending + posted-unassigned rows, scoped to the user" do
    mine  = pending_txn
    other = User.create!(email_address: "other@example.com", password: "password123")
    theirs = other.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")

    get transactions_url
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(mine)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(theirs)}", count: 0
  end

  test "assign charges the expense to the chosen account (assign_instrument!)" do
    txn = pending_txn
    patch assign_transaction_url(txn), params: { instrument: "bank_account-#{@account.id}" }
    assert_redirected_to transactions_path
    assert_equal @account, txn.reload.bank_account
    assert_nil txn.credit_card
  end

  test "assign with a blank instrument clears any assignment" do
    txn = pending_txn(bank_account: @account)
    patch assign_transaction_url(txn), params: { instrument: "" }
    assert_nil txn.reload.bank_account
    assert_nil txn.credit_card
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

  test "destroy reverses a posted transaction (reverse!)" do
    txn = pending_txn(status: "posted", bank_account: @account)
    delete transaction_url(txn)
    assert txn.reload.rejected?
  end

  test "cannot touch another user's transaction" do
    other = User.create!(email_address: "other2@example.com", password: "password123")
    theirs = other.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")
    patch confirm_transaction_url(theirs)
    assert_response :not_found
    assert theirs.reload.pending_review?
  end

  test "assign answers a turbo stream" do
    txn = pending_txn
    patch assign_transaction_url(txn), params: { instrument: "credit_card-#{@card.id}" }, as: :turbo_stream
    assert_response :success
    assert_equal @card, txn.reload.credit_card
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
    txn = @user.transactions.create!(amount_cents: 5_000, occurred_on: Date.new(2026, 7, 4),
                                     status: "posted", direction: "expense", credit_card: @card)
    assert_equal Date.new(2026, 8, 1), txn.billing_month
    get transactions_url(month: "2026-08")
    assert_select "##{ActionView::RecordIdentifier.dom_id(txn, :row)}"
    get transactions_url(month: "2026-07")
    assert_select "##{ActionView::RecordIdentifier.dom_id(txn, :row)}", count: 0
  end

  test "row edit Fatura select sets the manual flag; a later occurred_on edit leaves it" do
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    txn = @user.transactions.create!(amount_cents: 5_000, occurred_on: Date.new(2026, 7, 4),
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

  test "reversing a posted row never writes balance_cents / current_bill_cents (pure record)" do
    @account.update!(balance_cents: 100_000)
    @card.update!(current_bill_cents: 50_000)
    txn = @user.transactions.create!(amount_cents: 5_000, occurred_on: Date.current,
                                     status: "posted", direction: "expense", bank_account: @account)
    delete transaction_url(txn), params: { from: "ledger", month: Date.current.strftime("%Y-%m") }, as: :turbo_stream
    assert txn.reload.rejected?
    assert_equal 100_000, @account.reload.balance_cents
    assert_equal 50_000, @card.reload.current_bill_cents
    assert_equal 0, @user.transactions.spend.count
  end

  test "confirming a parked installment stub fans out the plan and supersedes the stub" do
    @card.update!(bill_due_day: 10, closing_offset_days: 10)
    stub = pending_txn(amount_cents: 500_000, merchant: "celular", occurred_on: Date.new(2026, 7, 3),
                       billing_month: Date.new(2026, 7, 1), credit_card: @card,
                       extraction: { "installments_count" => 10, "installment_total_raw" => "5000" })
    assert_difference -> { @user.transactions.where.not(installment_number: nil).count }, 10 do
      patch confirm_transaction_url(stub), params: { month: "2026-07" }, as: :turbo_stream
    end
    assert_equal "superseded", stub.reload.status
    assert_equal 1, @user.commitments.installment.count

    # A second confirm must NOT re-expand (the stub is already superseded).
    assert_no_difference -> { @user.transactions.where.not(installment_number: nil).count } do
      patch confirm_transaction_url(stub), params: { month: "2026-07" }, as: :turbo_stream
    end
  end

  test "a ledger month with 250 rows shows the show-more link; show_all renders them" do
    month = Date.current.beginning_of_month
    250.times do
      @user.transactions.create!(bank_account: @account, direction: "expense", status: "posted",
                                 amount_cents: 100, occurred_on: Date.current, billing_month: month)
    end
    get transactions_url(month: month.strftime("%Y-%m"))
    assert_select "a", text: I18n.t("transactions.ledger.show_more", locale: :"pt-BR")
    get transactions_url(month: month.strftime("%Y-%m"), show_all: 1)
    assert_response :success
  end

  test "create adds a posted expense and re-renders the ledger frame (not the h2 anchor)" do
    assert_difference -> { @user.transactions.spend.count }, 1 do
      post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
           params: { transaction: { amount_reais: "12,00", merchant: "Feira", occurred_on: Date.current.to_s },
                     instrument: "bank_account-#{@account.id}" }
    end
    txn = @user.transactions.order(:id).last
    assert_equal 1_200, txn.amount_cents
    assert_equal @account, txn.bank_account
    # Guards the id collision that duplicated the list: the stream targets the frame, not #ledger.
    assert_select "turbo-stream[action='replace'][target='movements_ledger']"
    assert_select "turbo-stream[action='replace'][target='ledger']", count: 0
  end

  test "manual create auto-assigns the lone card for crédito without an instrument token (issue 3)" do
    post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "30,00", occurred_on: Date.current.to_s, payment_method: "credito" } }
    txn = @user.transactions.order(:id).last
    assert_equal @card, txn.credit_card
    assert_nil txn.bank_account
    assert txn.assigned?, "should not land unassigned in the review tray"
  end

  test "manual create auto-assigns the lone account for pix without an instrument token (issue 3)" do
    post transactions_url(kind: "expense", month: Date.current.strftime("%Y-%m")), as: :turbo_stream,
         params: { transaction: { amount_reais: "30,00", occurred_on: Date.current.to_s, payment_method: "pix" } }
    txn = @user.transactions.order(:id).last
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
    assert_equal "credito", @user.transactions.order(:id).last.payment_method
  end

  test "new expense form renders the payment-method control and avatar instrument options" do
    get new_transaction_url(kind: "expense", month: Date.current.strftime("%Y-%m"))
    assert_response :success
    assert_select "[data-controller='entry-instrument']"
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
    cat = @user.categories.create!(name: "Mercado", color: "#22C55E", icon: "cart")
    @user.transactions.create!(bank_account: @account, category: cat, direction: "expense", status: "posted",
                               amount_cents: 100, occurred_on: Date.current, billing_month: Date.current.beginning_of_month)
    get transactions_url
    assert_response :success
    assert_select "[role='img'][aria-label=?]", I18n.t("transactions.hero.allocation_label", locale: :"pt-BR")
  end

  test "the transfer tab is hidden with a single account and shown with two (R5)" do
    get new_transaction_url(kind: "expense")
    assert_select "a[href*='kind=transfer']", count: 0

    @user.bank_accounts.create!(institution: @inst, nickname: "Segunda")
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
    txn = @user.transactions.order(:id).last
    assert_equal "income", txn.direction
    assert_equal future, txn.billing_month
    assert_predicate txn, :posted?
  end
end
