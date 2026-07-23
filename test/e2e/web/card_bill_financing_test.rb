require "test_helpers/e2e/pipeline_case"

# ROT-02 — parcelamento de fatura (founder 2026-07-22d): recording a bank-contracted
# installment plan on a closed bill's remainder. The BANK's numbers rule (count + parcela
# typed verbatim); parcels are DERIVED lines on the next faturas via bill_cents — never
# transaction rows — so destroying the financing is the whole rollback. Canonical figures
# on the ROT pack (bill 300.000¢): entrada 45.000 → remainder 255.000, financed as
# 6 × 47.000 = 282.000 (encargos 27.000, 4.500/parcel).
class E2E::WebCardBillFinancingTest < E2E::PipelineCase
  def finance!(scenario, count: 6, parcela: "470,00", financed: "2.550,00", entrada: "450,00")
    travel 1.minute
    # One submit (founder 2026-07-22e): the entrada rides the financing form and IS this
    # bill's payment — a normal Pay transfer from the chosen account.
    post finance_card_bill_url(scenario.closed_bill), params: {
      entrada_reais: entrada, bank_account_id: scenario.itau.id,
      financed_reais: financed, installments_count: count, installment_reais: parcela
    }
    # Harness gotcha: the query cache is per-THREAD, so the financings SELECT cached
    # empty on the test thread (scenario build) survives the server thread's INSERT —
    # force-refresh the association before any test-side money assertion.
    scenario.nubank_card.bill_financings.reload
  end

  def dispatch_reminders!
    Reminders::DailyDispatchJob.perform_now
    drain_jobs!
  end

  test "ROT-02: financing replaces the carryover — parcels ride the next bills as derived lines, never rows" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill
    next_month = bill.billing_month >> 1
    rows_before = s.account.transactions.count + 1   # only the entrada payment row lands

    finance! s

    bill.reload
    assert bill.financed?
    assert_equal "financed", bill.display_status
    assert bill.paid?, "a financed bill counts as paid everywhere — the tag alone says parcelada"
    assert_equal rows_before, s.account.transactions.count, "only the entrada row — parcels are never rows"

    entrada = bill.payments.posted.kept.sole
    assert_equal 45_000, entrada.amount_cents
    assert_equal s.itau.id, entrada.bank_account_id, "the entrada debits the chosen account"

    summary = MonthSummary.new(s.account, next_month)
    assert_nil summary.card_carryovers[s.nubank_card], "contracted plan replaces the rotativo carryover"
    assert_equal 47_000, summary.bill_totals[s.nubank_card], "next fatura = the parcela alone"

    assert_equal 47_000, s.nubank_card.bill_cents(bill.billing_month >> 6), "last parcel month"
    assert_equal 0,      s.nubank_card.bill_cents(bill.billing_month >> 7), "past the schedule"

    get transactions_url(month: next_month.strftime("%Y-%m"))
    assert_includes response.body,
                    I18n.t("card_bills.financing.line", month: I18n.l(bill.billing_month, format: :month_name, locale: :"pt-BR"),
                                                        no: 1, count: 6, locale: :"pt-BR")
    assert_brl 47_000, response.body
    assert_not_includes response.body, I18n.t("card_bills.carryover.estimated_charges", locale: :"pt-BR")

    get card_bill_url(bill)
    assert_includes response.body, I18n.t("card_bills.status.financed", locale: :"pt-BR")
    assert_includes response.body,
                    I18n.t("card_bills.financing.summary", count: 6, parcel: brl(47_000), total: brl(282_000), locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.financing.summary_fees", amount: brl(27_000), locale: :"pt-BR")
    assert_select "button.btn-primary[data-action='modal#open']", count: 0   # paid semantics: no Pagar CTA
  end

  test "ROT-02: cancel is the whole rollback — entrada reversed, plain carryover returns" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill
    next_month = bill.billing_month >> 1

    finance! s
    delete unfinance_card_bill_url(bill)

    assert_not bill.reload.financed?
    assert_equal 0, bill.paid_cents, "the form's entrada is reversed with the plan"
    summary = MonthSummary.new(s.account, next_month)
    assert_equal 300_000, summary.card_carryovers[s.nubank_card][:carryover_cents]
    assert_equal 47_148,  summary.card_carryovers[s.nubank_card][:finance_charges_cents]
    assert_equal 347_148, summary.bill_totals[s.nubank_card]
  end

  test "ROT-02: cancel keeps a payment that was recorded via Pagar before the plan" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner
    bill = s.closed_bill

    travel 1.minute
    post pay_card_bill_url(bill), params: { amount_reais: "450,00", bank_account_id: s.itau.id }
    finance! s, entrada: ""   # entrada already recorded — form field left blank
    delete unfinance_card_bill_url(bill)

    assert_not bill.reload.financed?
    assert_equal 45_000, bill.paid_cents, "a Pagar payment is not the form's to undo"
    summary = MonthSummary.new(s.account, bill.billing_month >> 1)
    assert_equal 255_000, summary.card_carryovers[s.nubank_card][:carryover_cents]
    assert_equal 40_076,  summary.card_carryovers[s.nubank_card][:finance_charges_cents]
  end

  test "ROT-02: the financed amount holds limit, released as parcels are billed" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner

    finance! s

    # At the anchor every parcel is still ahead (open bill month IS parcel 1's month).
    assert_equal 255_000, s.nubank_card.used_cents

    travel 3.months   # open month = parcel 4's month → 3 of 6 parcels remain
    assert_equal 127_500, s.nubank_card.used_cents
    travel 12.months
    assert_equal 0, s.nubank_card.used_cents, "schedule exhausted — limit fully released"
  end

  test "ROT-02: encargos split evenly with the remainder cents on parcel 1" do
    s = E2E::Scenario.build(:bill_revolving)
    fin = s.closed_bill.build_financing(
      account: s.account, installments_count: 7, installment_cents: 40_000,
      financed_cents: 255_000, first_charge_month: s.closed_bill.billing_month >> 1)
    assert_equal 25_000, fin.finance_charges_total_cents
    assert_equal 3_574, fin.finance_charges_for(1)   # 25.000 = 7×3.571 + 3 → the 3 land on parcel 1
    assert_equal 3_571, fin.finance_charges_for(2)
    assert_equal 25_000, (1..7).sum { |n| fin.finance_charges_for(n) }, "split is exact"
  end

  test "ROT-02: a financed bill leaves the rotativo — warning panel and overdue banner stop" do
    s = E2E::Scenario.build(:bill_revolving)
    dispatch_reminders!
    notification = Notification.find_by!(user: s.owner, kind: "card_overdue")
    sign_in_as s.owner
    bill = s.closed_bill

    get dashboard_url
    assert_select "#notification_#{notification.id}"

    finance! s

    get projection_card_bill_url(bill), params: { amount_reais: "100,00" }
    assert_not_includes response.body, I18n.t("card_bills.rotativo.below_total", locale: :"pt-BR"),
                        "no rotativo projection on a contracted plan"

    get dashboard_url
    assert_select "#notification_#{notification.id}", count: 0
    assert_nil notification.reload.dismissed_at, "derived, never dismissed"

    delete unfinance_card_bill_url(bill)
    get dashboard_url
    assert_select "#notification_#{notification.id}"   # cancel brings the banner back
  end

  test "ROT-02: the bank's numbers must cover the principal — negative juros is a typo" do
    s = E2E::Scenario.build(:bill_revolving)
    sign_in_as s.owner

    finance! s, count: 2, parcela: "100,00"   # 2 × 10.000 < 255.000

    assert_not s.closed_bill.reload.financed?
    assert_equal I18n.t("card_bills.finance.invalid", locale: :"pt-BR"), flash[:alert]
    assert_equal 0, s.closed_bill.paid_cents, "a rejected plan posts no entrada either"

    # The two entry points share ONE form: the bill-page disclosure and the modal's
    # "Parcelei" swap both render _financing_form.
    get card_bill_url(s.closed_bill)
    assert_includes response.body, I18n.t("card_bills.financing.offer", locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.financing.short_cta", locale: :"pt-BR")
    assert_select "#financing_entrada_page"
    assert_select "#financing_entrada_modal"
  end
end
