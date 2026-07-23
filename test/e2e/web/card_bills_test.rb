require "test_helpers/e2e/pipeline_case"

# BILL-01..04 — the bill spine (.plans/credit-cards 05, phase 1): close it, notify with a
# pay CTA, pay it as a TRANSFER (never an expense — the month must never count a card
# spend twice), unpay reverses everything, source-less payments move no tracked balance.
class E2E::WebCardBillsTest < E2E::PipelineCase
  # BILL-01 — close → card_due golden with pay framing + deep link to the fresh bill.
  test "card_due after close: payable golden body and bill-page url" do
    s = push_ready(E2E::Scenario.build(:solo_basic))
    s.nubank_card.update!(bill_due_day: (Date.current + 1).day, closing_offset_days: 7)
    s.expense(merchant: "Compra Fechada", category: "Outros", instrument: s.nubank_card,
              cents: 25_000, on: Date.current - 10)

    CardBills::CloseScanJob.perform_now   # the production morning order: close, then remind
    dispatch_reminders!

    bill = s.nubank_card.card_bills.sole
    assert_equal 25_000, bill.effective_total_cents
    assert_wa_reply s.jid,
      equals: "📄 A fatura do *Nubank* fechou em R$ 250,00 e vence amanhã. Dá pra pagar pelo app. 💙"
    notification = Notification.find_by!(user: s.owner, kind: "card_due")
    assert_equal bill.id, notification.payload["card_bill_id"]
    assert_equal "/card_bills/#{bill.id}", Notifications.url_for(notification)
  end

  # BILL-01 — the close scan is idempotent (unique index) and never touches the open month.
  test "close scan: run twice, one row, open month stays a query" do
    s = E2E::Scenario.build(:bill_closed)

    2.times { CardBills::CloseScanJob.perform_now }

    assert_equal 1, s.nubank_card.card_bills.count
    assert_equal Date.current.beginning_of_month, s.closed_bill.billing_month
    assert_nil s.nubank_card.card_bills.find_by(billing_month: s.nubank_card.current_open_bill_month)
  end

  # BILL-02 — pay in full from checking: derived balance drops by exactly the amount, the
  # STORED balance column never moves (pure record), sobra/saídas unchanged (the obligation
  # was already in faturas), bill reads paga.
  test "pay full from checking: transfer leg, exact balance drop, sobra invariant" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill    = s.closed_bill
    month   = bill.billing_month
    summary = -> { MonthSummary.new(s.account, month) }
    before  = summary.call
    saidas_before, faturas_before, sobra_before =
      before.saidas_cents, before.faturas_cents, before.remaining_cents
    assert_equal 125_000, faturas_before, "pack calibration rides through faturas"

    travel 1.minute   # order the payment after the balance anchor (frozen-clock gotcha)
    post pay_card_bill_url(bill), params: {
      amount_reais: "1.250,00", paid_on: Date.current.iso8601, bank_account_id: s.itau.id
    }
    assert_redirected_to card_bill_url(bill)

    assert_equal "paid", bill.reload.status
    assert_equal 125_000, bill.paid_cents
    assert_equal 250_000 - 125_000, s.itau.derived_balance_cents, "source leg drops the derived balance"
    assert_equal 250_000, s.itau.reload.balance_cents, "stored balance is never written"

    after = summary.call
    assert_equal saidas_before,  after.saidas_cents,  "a fatura payment is never a saída"
    assert_equal faturas_before, after.faturas_cents, "the obligation stays in faturas — counted once"
    assert_equal sobra_before,   after.remaining_cents, "sobra invariant at pay time"

    payment = bill.payments.sole
    assert payment.transfer?
    assert_equal s.nubank_card.id, payment.transfer_to_credit_card_id
    assert_nil payment.credit_card_id, "the payment is NOT a card transaction row"
    assert_equal month, payment.billing_month
    assert payment.billing_month_manual?, "paying July's bill in August must not re-bucket"
  end

  # BILL-03 — unpay reverses all of it.
  test "unpay: bill back to em aberto, derived balance restored" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    travel 1.minute
    post pay_card_bill_url(s.closed_bill), params: {
      amount_reais: "1.250,00", bank_account_id: s.itau.id
    }
    payment = s.closed_bill.payments.sole

    patch unpay_card_bill_url(s.closed_bill, payment_id: payment.id)

    assert_equal "rejected", payment.reload.status
    assert_equal "unpaid", s.closed_bill.reload.status
    assert_equal 250_000, s.itau.derived_balance_cents, "the reversed transfer un-drops the balance"
  end

  # BILL-04 — P0 #4: a source-less payment records paid status/amount, moves no balance.
  test "sourceless payment: paga with zero balance effect" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    travel 1.minute

    post pay_card_bill_url(s.closed_bill), params: { amount_reais: "1.250,00", bank_account_id: "" }

    assert_equal "paid", s.closed_bill.reload.status
    assert_nil s.closed_bill.payments.sole.bank_account_id
    assert_equal 250_000, s.itau.derived_balance_cents, "no tracked balance moved"
  end

  # BILL-01 — a late capture with a pre-closing date lands on the CLOSED bill: the computed
  # total shifts (live query, no frozen copy) and the page shows the new figure.
  test "late capture onto a closed bill shifts the computed total and the page" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    s.expense(merchant: "Capturada Atrasada", category: "Outros", instrument: s.nubank_card,
              cents: 4_990, on: Date.current.beginning_of_month + 1)   # pre-closing date

    assert_equal 129_990, s.closed_bill.computed_total_cents

    get card_bill_url(s.closed_bill)
    assert_response :success
    assert_brl 129_990, response.body, "the bill page shows the drifted total"
  end

  # Partial payments accumulate (no paid-once flag): two partials → parcialmente paga → paga.
  test "partial payments sum: parcialmente paga then paga" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    travel 1.minute

    post pay_card_bill_url(s.closed_bill), params: { amount_reais: "500,00", bank_account_id: s.itau.id }
    assert_equal "partially_paid", s.closed_bill.reload.status
    assert_equal 50_000, s.closed_bill.paid_cents

    post pay_card_bill_url(s.closed_bill), params: { amount_reais: "750,00", bank_account_id: s.itau.id }
    assert_equal "paid", s.closed_bill.reload.status
    assert_equal 250_000 - 125_000, s.itau.derived_balance_cents
  end

  # The dashboard card banner derives from the bill, never the row: pay → banner gone,
  # undo → banner back. The notification is NOT dismissed on pay (payment is reversible),
  # the render simply skips a paid bill's card_due/card_overdue alert.
  test "overdue banner hides once the bill is paid and returns on undo" do
    s = E2E::Scenario.build(:bill_rotativo)
    dispatch_reminders!
    notification = Notification.find_by!(user: s.owner, kind: "card_overdue")
    sign_in_as s.owner

    get dashboard_url
    assert_select "#notification_#{notification.id}"

    travel 1.minute
    post pay_card_bill_url(s.closed_bill), params: {
      amount_reais: "3.000,00", bank_account_id: s.itau.id
    }
    assert s.closed_bill.reload.paid?
    get dashboard_url
    assert_select "#notification_#{notification.id}", count: 0
    assert_nil notification.reload.dismissed_at, "derived, never dismissed"

    patch unpay_card_bill_url(s.closed_bill, payment_id: s.closed_bill.payments.sole.id)
    get dashboard_url
    assert_select "#notification_#{notification.id}"
  end

  # Founder round (2026-07-22): a bill never reads "vencida" forever — an unpaid remainder
  # absorbed by a NEWER closed bill (Carryover) reads "na fatura seguinte" and the cards
  # page badges only the newest bill (same debt never announced twice); once fully paid
  # after due, the badge says "paga em atraso".
  test "rolled and paid_late refine display_status; cards badge probes only the newest bill" do
    s = E2E::Scenario.build(:bill_rotativo)
    bill = s.closed_bill                        # due day 10, anchor the 20th → past due
    travel 1.minute
    CardBills::Pay.call(bill, amount_cents: 100_000, paid_on: Date.current,
                        bank_account: s.itau, created_by: s.owner)
    assert_equal "overdue", bill.display_status, "partial past due is still vencida"

    # Next cycle: new spend closes into a NEW bill — the remainder rolls forward.
    travel 1.month
    s.expense(merchant: "Mercado Novo", category: "Outros", instrument: s.nubank_card,
              cents: 5_000, on: Date.current.beginning_of_month + 1)   # pre-closing → this month's bill
    CardBills::CloseScan.ensure_for(s.nubank_card)
    newest = s.nubank_card.card_bills.order(:billing_month).last
    assert_not_equal bill.id, newest.id, "the next month's bill materialized"
    assert bill.rolled?
    assert_equal "rolled", bill.display_status

    # Founder 2026-07-23 re-pin: the index shows the last 3 bills ("Últimas faturas"),
    # so the rolled bill IS listed — but wearing its rolled status, never as payable debt
    # (its remainder was carried into the newest bill; Pagar lives on the bill page).
    sign_in_as s.owner
    get credit_cards_url
    assert_select "a[href='#{card_bill_path(newest)}']"
    assert_select "a[href='#{card_bill_path(bill)}']" do
      assert_select ".badge", text: I18n.t("card_bills.status.rolled", locale: :"pt-BR")
    end

    travel 1.minute
    CardBills::Pay.call(bill, amount_cents: 200_000, paid_on: Date.current,
                        bank_account: s.itau, created_by: s.owner)
    assert_equal "paid_late", bill.display_status
  end

  # Closed-faturas history (founder ask, 2026-07-22): every bill with status + what was
  # paid, rows linking to the bill page where Pagar lives. Root cards only.
  test "bills history lists closed bills with status and paid amount" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    travel 1.minute
    post pay_card_bill_url(s.closed_bill), params: { amount_reais: "500,00", bank_account_id: s.itau.id }

    get bills_credit_card_url(s.nubank_card)
    assert_response :success
    assert_select "a[href='#{card_bill_path(s.closed_bill)}']"
    assert_includes response.body, I18n.t("card_bills.status.overdue", locale: :"pt-BR")
    assert_includes response.body, I18n.t("credit_cards.bills.paid", amount: brl(50_000), locale: :"pt-BR")
  end

  # Founder 2026-07-23: the hub tile's card row goes straight to the closed month's bill
  # page; the open month (no bill row yet) keeps the inline lines toggle.
  test "bills tile links a closed month's card row to its bill page" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner

    get transactions_url
    assert_response :success
    assert_select "#bills_tile a[href='#{card_bill_path(s.closed_bill)}']"

    get transactions_url(month: s.nubank_card.current_open_bill_month.strftime("%Y-%m"))
    assert_select "#bills_tile a[href^='/card_bills/']", count: 0
  end

  # LGPD: the account cascade must erase bills, payment transfers AND reconciliation
  # imports without FK trips (found twice by the demo-seed wipe / exploratory walk:
  # card_bills and document_imports both referenced instruments mid-cascade).
  test "account destroy cascades closed bills, payment transfers and reconciliation imports" do
    s = E2E::Scenario.build(:bill_closed)
    travel 1.minute
    CardBills::Pay.call(s.closed_bill, amount_cents: 50_000, paid_on: Date.current,
                        bank_account: s.itau, created_by: s.owner)
    [ { credit_card: s.nubank_card }, { bank_account: s.itau } ].each do |target|
      import = s.account.document_imports.new(purpose: "reconciliation", checksum: SecureRandom.hex,
                                              period: Date.current.beginning_of_month, **target)
      import.file.attach(io: StringIO.new("%PDF-1.4"), filename: "f.pdf", content_type: "application/pdf")
      import.save!
    end

    bill_id = s.closed_bill.id
    assert_nothing_raised { s.account.destroy! }
    assert_equal 0, CardBill.where(id: bill_id).count
  end

  # Founder 2026-07-22c: bill lines are editable in place like Movimentos — rows link
  # into the shared entry sheet; save/delete responds with a full-page refresh stream
  # (the total, conferência state and carryover lines shift with the row).
  test "bill lines edit/delete in place via the shared entry sheet" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill
    line = s.account.transactions.find_by!(merchant: "Na Borda do Corte")

    get card_bill_url(bill)
    assert_select "a[href=?]", edit_transaction_path(line, context: "bill")

    patch transaction_path(line), as: :turbo_stream,
          params: { from: "ledger", context: "bill", transaction: { merchant: "Corte Novo" } }
    assert_includes response.body, %(<turbo-stream action="refresh">)
    assert_equal "Corte Novo", line.reload.merchant

    delete transaction_path(line), as: :turbo_stream, params: { from: "ledger", context: "bill" }
    assert_includes response.body, %(<turbo-stream action="refresh">)
    assert line.reload.soft_deleted?
    assert_equal 110_000, bill.reload.computed_total_cents, "the erased line left the bill"
  end

  private

  def push_ready(s)
    s.wa_verified!(consent: true)
    s.owner.notification_prefs.update!(wa_intro_sent_at: Time.current)
    wa_connect!
    s
  end

  def dispatch_reminders!
    Reminders::DailyDispatchJob.perform_now
    drain_jobs!
  end
end
