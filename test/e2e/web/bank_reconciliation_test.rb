require "test_helpers/e2e/pipeline_case"

# REC-05 — bank-extrato reconciliation (.plans/credit-cards 05, phase 5): the drift
# headline against the derived balance as-of the statement end, transfer legs read as the
# extrato reads them, only-in-app proposes removal (default manter), and the CSV path
# runs with NO LLM and NO cap consumed.
class E2E::WebBankReconciliationTest < E2E::PipelineCase
  test "REC-05: PDF extrato → exact drift headline → create + remove via apply" do
    s = E2E::Scenario.build(:solo_basic).add_savings_account!
    sign_in_as s.owner
    s.itau.update!(balance_cents: 100_000)
    travel 1.minute   # rows below carry a fresh created_at, AFTER the balance anchor
    prev = Date.current.beginning_of_month << 1
    fresh = lambda do |merchant, cents, on, extra = {}|
      s.account.transactions.create!(
        merchant: merchant, direction: "expense", status: "posted", source: "manual",
        amount_cents: cents, occurred_on: on, confirmed_at: Time.current,
        bank_account: s.itau, created_by: s.owner, **extra)
    end
    fresh.call("Padaria Real", 2_000, prev + 9)
    fresh.call("Guardado do mês", 5_000, prev + 11,
               { direction: "transfer", transfer_to_bank_account: s.savings_account })      # outgoing transfer leg
    ghost = fresh.call("Lançamento Fantasma", 3_000, prev + 15)                      # only in the app

    post reconciliations_url, params: { bank_account_id: s.itau.id, period: prev.strftime("%Y-%m"),
      file: fixture_file_upload("imports/statement.pdf", "application/pdf") }
    import = s.account.document_imports.reconciliation.sole
    assert_redirected_to reconciliation_url(import)

    Imports::DocumentExtractor.stub(:call, ->(*_a, **_k) { canned_extrato(prev) }) do
      perform_enqueued_jobs
    end
    assert_equal "extracted", import.reload.status

    # derived as-of prev-month end: 100.000 − 2.000 − 5.000 − 3.000 = 90.000; the bank
    # closes at 89.500 → drift of exactly R$ 5,00.
    get reconciliation_url(import)
    assert_includes response.body,
                    I18n.t("reconciliations.show.balance_drift", amount: brl(500), locale: :"pt-BR")

    diff = Reconciliation::Diff.call(rows: Reconciliation.rows_from_extraction(import.extraction),
      scope: Reconciliation::BankPeriodScope.new(bank_account: s.itau, month: prev))
    assert_equal 2, diff.matched.size, "the expense AND the transfer leg both match extrato debits"
    tarifa = diff.only_in_source.sole
    assert_equal [ ghost ], diff.only_in_app

    post apply_reconciliation_url(import), params: { create: [ tarifa.digest ], move: [ ghost.id ] }

    created = s.account.transactions.find_by!(merchant: "TARIFA PACOTE")
    assert_equal s.itau.id, created.bank_account_id
    assert_equal prev, created.billing_month, "bank rows bucket by calendar month"
    assert created.expense?
    assert ghost.reload.soft_deleted?, "only-in-app on the bank side removes the duplicate"
    assert_equal "applied", import.reload.status
  end

  test "REC-05: CSV extrato runs with NO LLM and consumes NO cap" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner

    # No extractor stub: an LLM call would attempt real HTTP and fail the import.
    post reconciliations_url, params: { bank_account_id: s.itau.id, period: "2026-06",
      file: fixture_file_upload("imports/sample.csv", "text/csv") }
    csv_import = s.account.document_imports.reconciliation.sole
    perform_enqueued_jobs
    assert_equal "extracted", csv_import.reload.status
    assert csv_import.extraction["rows"].any?

    # The slot is still free: a PDF for the same account this month is accepted.
    post reconciliations_url, params: { bank_account_id: s.itau.id, period: "2026-06",
      file: fixture_file_upload("imports/statement.pdf", "application/pdf") }
    assert_equal 2, s.account.document_imports.reconciliation.count, "CSV never consumed the LLM slot"
  end

  # The conferir entry lives on the account EDIT page (not the index rows); the create
  # form carries "saldo inicial" but the edit form does not — a persisted account's
  # balance changes only through Ajustar saldo, which records the delta as a visible
  # ledger row (income up / expense down). Deleting that row IS the rollback.
  test "conferir on edit page, saldo inicial create-only, ajustar saldo is a ledger delta" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner
    s.itau.update!(balance_cents: 50_000)

    get bank_accounts_url
    assert_select "form[action=?]", reconciliations_path, count: 0
    assert_select "#bank_account_form input[name='bank_account[balance_reais]']"

    get edit_bank_account_url(s.itau)
    assert_select "form[action=?]", reconciliations_path
    assert_select "#bank_account_form input[name='bank_account[balance_reais]']", count: 0

    travel 1.minute
    patch adjust_balance_bank_account_url(s.itau), params: { balance_reais: "600,00" }
    up = s.itau.transactions.order(:id).last
    assert up.income?, "raising the balance records an income delta"
    assert_equal 10_000, up.amount_cents
    assert_equal I18n.t("bank_accounts.adjust.transaction_merchant", locale: :"pt-BR"), up.merchant
    assert_equal 60_000, s.itau.derived_balance_cents

    patch adjust_balance_bank_account_url(s.itau), params: { balance_reais: "450,00" }
    down = s.itau.transactions.order(:id).last
    assert down.expense?, "lowering the balance records an expense delta"
    assert_equal 15_000, down.amount_cents
    assert_equal 45_000, s.itau.derived_balance_cents

    down.soft_delete!(by: s.owner)   # the promised rollback: delete the adjustment row
    assert_equal 60_000, s.itau.derived_balance_cents, "deleting the adjustment reverts the balance"
  end

  private

  # The bank's April: both our rows as debits (the transfer leg is just a debit to the
  # bank), one tarifa we never captured, and the closing balance for the drift headline.
  def canned_extrato(month)
    { "format" => "pdf", "confidence" => 0.9,
      "meta" => { "closing_balance_cents" => 89_500, "period_end" => month.end_of_month.iso8601 },
      "rows" => [
        { "date" => (month + 9).iso8601,  "description" => "PADARIA REAL",     "amount_cents" => 2_000,
          "direction" => "out", "installment" => nil, "section_last4" => nil },
        { "date" => (month + 11).iso8601, "description" => "TRANSF GUARDADO",  "amount_cents" => 5_000,
          "direction" => "out", "installment" => nil, "section_last4" => nil },
        { "date" => (month + 12).iso8601, "description" => "TARIFA PACOTE",    "amount_cents" => 1_990,
          "direction" => "out", "installment" => nil, "section_last4" => nil }
      ] }
  end
end
