require "test_helpers/e2e/pipeline_case"

# ROT-01 — rotativo (.plans/credit-cards 05 phase 3), frozen rates 15,09/9,26: the warning
# panel to the centavo, the carryover + estimated-encargos projection lines (NEVER rows),
# the estimates-never-coexist-with-stated rule, the negative carryover, and the
# card_overdue escalation with its golden body.
class E2E::WebCardBillRevolvingTest < E2E::PipelineCase
  test "ROT-01: partial payment warning panel renders the canonical figures" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner

    get projection_card_bill_url(s.closed_bill), params: { amount_reais: "450,00" }
    assert_response :success

    assert_includes response.body, I18n.t("card_bills.rotativo.below_total", locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.rotativo.below_total_rate", rate: "15,1", locale: :"pt-BR")
    assert_brl 255_000, response.body, "fica devendo"
    assert_brl 295_076, response.body, "vem na próxima fatura = financed + cycle cost"
    assert_includes response.body,
                    I18n.t("card_bills.rotativo.next_bill_fees", amount: brl(40_076), locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.rotativo.parcelamento_hint", locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.rotativo.cap_reassurance", months: 5, locale: :"pt-BR")
    assert_not_includes response.body, I18n.t("card_bills.rotativo.assumed_minimum", locale: :"pt-BR"),
                        "450,00 IS the 15% assumed minimum — the atraso band stays off"
  end

  test "ROT-01: below the assumed minimum adds the atraso band, labeled as an assumption" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner

    get projection_card_bill_url(s.closed_bill), params: { amount_reais: "100,00" }
    assert_includes response.body, I18n.t("card_bills.rotativo.assumed_minimum", locale: :"pt-BR")
  end

  test "ROT-01: carryover + encargos ride the next month as labeled lines, never rows" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill
    next_month = bill.billing_month >> 1
    rows_before = s.account.transactions.count

    travel 1.minute
    post pay_card_bill_url(bill), params: { amount_reais: "450,00", bank_account_id: s.itau.id }

    summary = MonthSummary.new(s.account, next_month)
    carry = summary.card_carryovers[s.nubank_card]
    assert_equal 255_000, carry[:carryover_cents]
    assert_equal 40_076,  carry[:finance_charges_cents]
    assert_equal 295_076, summary.bill_totals[s.nubank_card], "next month's fatura figure = carryover + finance_charges"

    assert_equal rows_before + 1, s.account.transactions.count, "ONLY the payment row exists — projections are never rows"
    assert_equal 400_000, s.itau.reload.balance_cents, "stored balance never written"

    get transactions_url(month: next_month.strftime("%Y-%m"))
    assert_includes response.body,
                    I18n.t("card_bills.carryover.from_bill", month: I18n.l(bill.billing_month, format: :month_name, locale: :"pt-BR"), locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.carryover.estimated_charges", locale: :"pt-BR")
    assert_brl 255_000, response.body
    assert_brl 40_076, response.body
  end

  # Pinned rule, refined 2026-07-22: the NEXT bill's stated_total rules — and drops our
  # estimate lines — only once the conferência RESOLVES. While pending, our figure
  # (rows + carryover estimate) keeps ruling every surface.
  test "ROT-01: NEXT bill's stated rules only after the check resolves" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill
    next_month = bill.billing_month >> 1
    travel 1.minute
    post pay_card_bill_url(bill), params: { amount_reais: "450,00", bank_account_id: s.itau.id }

    next_bill = s.nubank_card.card_bills.create!(
      account: s.account, billing_month: next_month,
      closed_on: s.nubank_card.closing_date(next_month), due_on: s.nubank_card.due_date(next_month),
      stated_total_cents: 295_000, created_by: s.owner)

    # Bank says 295.000; our estimate is 255.000 carry + 40.076 encargos = 295.076 → pending.
    assert next_bill.divergence_pending?
    summary = MonthSummary.new(s.account, next_month)
    assert_not_nil summary.card_carryovers[s.nubank_card], "estimates keep showing while pending"
    assert_equal 295_076, summary.bill_totals[s.nubank_card], "our figure rules until resolved"

    # Resolve via the adjustment (the 76¢ estimate gap) → the bank's number IS the figure,
    # and the carryover lines STAY as its breakdown (founder 2026-07-22c — resolution
    # equalized our figure with the bank's, so the lines keep summing to the total).
    post adjust_card_bill_url(next_bill)
    assert_not next_bill.reload.divergence_pending?
    summary = MonthSummary.new(s.account, next_month)
    assert_not_nil summary.card_carryovers[s.nubank_card], "the breakdown lines persist after accepting"
    assert_equal 295_000, summary.bill_totals[s.nubank_card], "the bank's number IS the figure now"
  end

  test "ROT-01: overpay yields a negative carryover that reduces the next figure, no finance_charges" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill
    travel 1.minute
    post pay_card_bill_url(bill), params: { amount_reais: "3.100,00", bank_account_id: s.itau.id }

    summary = MonthSummary.new(s.account, bill.billing_month >> 1)
    carry = summary.card_carryovers[s.nubank_card]
    assert_equal(-10_000, carry[:carryover_cents])
    assert_equal 0, carry[:finance_charges_cents], "a credit charges nothing"
    assert_equal(-10_000, summary.bill_totals[s.nubank_card])
  end

  test "ROT-01: card_overdue fires once past due with the golden body, never again, never for paid" do
    s = push_ready(E2E::Scenario.build(:bill_revolving))

    2.times { dispatch_reminders! }

    assert_equal 1, Notification.where(user: s.owner, kind: "card_overdue").count, "one row ever per bill"
    assert_equal 1, fake_sidecar.messages_to(s.jid).size
    assert_wa_reply s.jid,
      equals: "⚠️ A fatura do *Nubank* venceu e ainda tem R$ 3.000,00 em aberto. O rotativo é caro — dá pra pagar pelo app. 💙"
    notification = Notification.find_by!(user: s.owner, kind: "card_overdue")
    assert_equal "/card_bills/#{s.closed_bill.id}", Notifications.url_for(notification)

    paid = push_ready(E2E::Scenario.build(:bill_revolving))
    CardBills::Pay.call(paid.closed_bill, amount_cents: 300_000, paid_on: Date.current,
                        bank_account: paid.itau, created_by: paid.owner)
    dispatch_reminders!
    assert_not Notification.exists?(user: paid.owner, kind: "card_overdue"), "paid bills never escalate"
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
