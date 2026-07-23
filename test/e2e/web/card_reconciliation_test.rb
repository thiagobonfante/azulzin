require "test_helpers/e2e/pipeline_case"

# REC-01 — card-bill reconciliation (.plans/credit-cards 03, phase 4), lane P: the REAL
# upload → job → review → apply flow with canned extraction rows (the AI stays the only
# stub). One missing (create), one ours-only (move), one 1-centavo mismatch (fix),
# matched collapsed; replay creates zero new rows; the monthly cap is per instrument and
# failed runs never consume it.
class E2E::WebCardReconciliationTest < E2E::PipelineCase
  test "REC-01: upload → diff buckets → apply (create/move/fix) → replay is a no-op" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    post reconciliations_url, params: {
      credit_card_id: s.nubank_card.id, period: bill.billing_month.iso8601,
      file: fixture_file_upload("imports/statement.pdf", "application/pdf") }
    import = s.account.document_imports.reconciliation.sole
    assert_redirected_to reconciliation_url(import)
    assert_equal bill.billing_month, import.period

    Imports::DocumentExtractor.stub(:call, ->(*_a, **_k) { canned_extraction }) do
      perform_enqueued_jobs
    end
    import.reload
    assert_equal "extracted", import.status
    assert import.proposals.blank?, "reconciliation runs never build onboarding proposals"

    get reconciliation_url(import)
    assert_response :success
    assert_includes response.body, I18n.t("reconciliations.show.matched.one", locale: :"pt-BR")
    assert_includes response.body, "TAXA DE ANUIDADE"

    diff = Reconciliation::Diff.call(
      rows: Reconciliation.rows_from_extraction(import.extraction),
      scope: Reconciliation::CardBillScope.new(credit_card: s.nubank_card, month: bill.billing_month))
    missing = diff.only_in_source.sole
    ours    = diff.only_in_app.sole
    typo    = diff.amount_mismatch.sole.last
    assert_equal "Na Borda do Corte", ours.merchant
    assert_equal 50_000, typo.amount_cents

    rows_before = s.account.transactions.count
    post apply_reconciliation_url(import),
         params: { create: [ missing.digest ], move: [ ours.id ], fix: [ typo.id ] }

    created = s.account.transactions.find_by!(merchant: "TAXA DE ANUIDADE")
    assert_equal "reconciliation", created.source
    assert_equal "recon-#{import.id}-#{missing.digest}", created.source_message_id
    assert_equal bill.billing_month, created.billing_month
    assert created.billing_month_manual?
    assert_equal 4_990, created.amount_cents
    assert_equal bill.billing_month >> 1, ours.reload.billing_month, "ours-only moved to the next fatura"
    assert ours.billing_month_manual?
    assert_equal 49_999, typo.reload.amount_cents, "corrected to the bank's centavo"
    assert_equal "applied", import.reload.status
    assert_equal rows_before + 1, s.account.transactions.count

    # Replay the same run (service-level, as if re-reviewed): zero new rows — the created
    # twin now MATCHES its bank row, and the dedup key backstops any drift.
    import.update!(status: "extracted")
    Reconciliation::Apply.call(
      import: import, accepted: { create: [ missing.digest ], move: [], fix: [] },
      scope: Reconciliation::CardBillScope.new(credit_card: s.nubank_card, month: bill.billing_month))
    assert_equal rows_before + 1, s.account.transactions.count, "replaying created nothing"
  end

  test "REC-01 cap: one LLM run per card per month, failed never consumes, CSV rides free" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    month = s.closed_bill.billing_month.iso8601

    post reconciliations_url, params: { credit_card_id: s.nubank_card.id, period: month,
      file: fixture_file_upload("imports/statement.pdf", "application/pdf") }
    first = s.account.document_imports.reconciliation.sole

    post reconciliations_url, params: { credit_card_id: s.nubank_card.id, period: month,
      file: fixture_file_upload("imports/no_text.pdf", "application/pdf") }
    follow_redirect!
    assert_includes response.body,
                    I18n.t("reconciliations.create.monthly_cap", locale: :"pt-BR",
                           date: I18n.l(Date.current.next_month.beginning_of_month, format: :short, locale: :"pt-BR"))
    assert_equal 1, s.account.document_imports.reconciliation.count, "the refused upload created nothing"

    # A failed run gives the slot back.
    first.update!(status: "failed")
    post reconciliations_url, params: { credit_card_id: s.nubank_card.id, period: month,
      file: fixture_file_upload("imports/no_text.pdf", "application/pdf") }
    assert_equal 2, s.account.document_imports.reconciliation.count

    # A second CARD has its own slot (P0 #2: per instrument, not per account).
    other = s.account.credit_cards.create!(institution: s.nubank_card.institution,
                                           nickname: "C6", bill_due_day: 10, created_by: s.owner)
    post reconciliations_url, params: { credit_card_id: other.id, period: month,
      file: fixture_file_upload("imports/pages26.pdf", "application/pdf") }
    assert_equal 3, s.account.document_imports.reconciliation.count

    # CSV parses deterministically — no LLM, no cap, even with the slot consumed.
    post reconciliations_url, params: { credit_card_id: s.nubank_card.id, period: month,
      file: fixture_file_upload("imports/sample.csv", "text/csv") }
    assert_equal 4, s.account.document_imports.reconciliation.count
  end

  # SUB-01 tie-in (04 §3): an unknown plastic in the fatura's sections becomes a proposed
  # sub-card; its section's rows post to the fresh sub-card, not the root.
  test "unknown fatura sections become sub-cards and catch their rows on apply" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    post reconciliations_url, params: {
      credit_card_id: s.nubank_card.id, period: bill.billing_month.iso8601,
      file: fixture_file_upload("imports/statement.pdf", "application/pdf") }
    import = s.account.document_imports.reconciliation.sole
    extraction = canned_extraction.merge(
      "meta" => { "card" => { "sections" => [
        { "last4" => "9911", "holder" => "@FILHA", "is_virtual" => false } ] } })
    extraction["rows"] << { "date" => bill.closed_on.iso8601, "description" => "LANCHONETE ESCOLA",
                            "amount_cents" => 2_500, "direction" => "out",
                            "installment" => nil, "section_last4" => "9911" }
    Imports::DocumentExtractor.stub(:call, ->(*_a, **_k) { extraction }) do
      perform_enqueued_jobs
    end

    get reconciliation_url(import)
    assert_includes response.body, I18n.t("reconciliations.show.sections", locale: :"pt-BR")
    assert_includes response.body, "@FILHA"

    diff = Reconciliation::Diff.call(rows: Reconciliation.rows_from_extraction(import.reload.extraction),
      scope: Reconciliation::CardBillScope.new(credit_card: s.nubank_card, month: bill.billing_month))
    escola = diff.only_in_source.find { |r| r.section_last4 == "9911" }

    post apply_reconciliation_url(import), params: { sections: [ "9911" ], create: [ escola.digest ] }

    sub = s.nubank_card.children.kept.find_by!(last4: "9911")
    assert_equal "@FILHA", sub.nickname
    assert sub.physical?
    created = s.account.transactions.find_by!(merchant: "LANCHONETE ESCOLA")
    assert_equal sub.id, created.credit_card_id, "the section's row posts to the fresh sub-card"
    assert_equal bill.billing_month, created.billing_month
  end

  private

  # The bank's side of the bill_closed pack (125.000¢ = 60.000 + 50.000 + 15.000):
  # Mercado matches; Farmácia comes 1 centavo lower (the typo case); the anuidade only
  # exists at the bank; "Na Borda do Corte" is missing (the bank rolled it forward).
  def canned_extraction
    prev = Date.current.beginning_of_month << 1
    { "format" => "pdf", "meta" => {}, "confidence" => 0.9, "rows" => [
      { "date" => (prev + 14).iso8601, "description" => "MERCADO GRANDE",   "amount_cents" => 60_000,
        "direction" => "out", "installment" => nil, "section_last4" => nil },
      { "date" => (prev + 19).iso8601, "description" => "FARMACIA CENTRAL", "amount_cents" => 49_999,
        "direction" => "out", "installment" => nil, "section_last4" => nil },
      { "date" => (prev + 20).iso8601, "description" => "TAXA DE ANUIDADE", "amount_cents" => 4_990,
        "direction" => "out", "installment" => nil, "section_last4" => nil }
    ] }
  end
end
