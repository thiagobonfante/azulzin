require "test_helper"
require_relative "../../test_helpers/import_extraction_fixtures"

# Phase 3 intelligence: income/commitment proposals from classified rows, exclusions, and the
# cross-file transfer reconciler.
class Imports::RecurringTest < ActiveSupport::TestCase
  include ImportExtractionFixtures

  LABELS = [
    { "id" => 0, "label" => "income", "merchant_canonical" => "Soma Coop", "commitment_name" => "Salário",
      "category_guess" => nil, "schedule_day" => 3, "confidence" => 0.85 },
    { "id" => 1, "label" => "fixed_bill", "merchant_canonical" => "Copel", "commitment_name" => "Energia (Copel)",
      "category_guess" => nil, "schedule_day" => 22, "confidence" => 0.9 },
    { "id" => 2, "label" => "installment", "merchant_canonical" => "Seguro", "commitment_name" => "Seguro incêndio",
      "category_guess" => nil, "schedule_day" => 5, "confidence" => 0.9 },
    { "id" => 3, "label" => "subscription", "merchant_canonical" => "Netflix", "commitment_name" => "Netflix",
      "category_guess" => nil, "schedule_day" => nil, "confidence" => 0.9 }
  ].freeze

  setup { @user = users(:confirmed) }

  # ── classifier transport hardening ──────────────────────────────────────────
  test "long row lists batch per 80 with globally-stable ids" do
    rows = Array.new(81) { |i| { "date" => nil, "description" => "R#{i}", "amount_cents" => 100, "direction" => "out", "signals" => [] } }
    sent = []
    fake = Object.new
    fake.define_singleton_method(:chat) do |messages:, schema:|
      sent << JSON.parse(messages.last[:content])
      ImportExtractionFixtures::FakeResult.new({ "rows" => [] })
    end
    Imports::RecurringClassifier.call(rows, client: fake)
    assert_equal 2, sent.size
    assert_equal 80, sent.first.size
    assert_equal [ 80 ], sent.last.map { it["id"] } # ids continue across batches
  end

  test "an unparseable classification raises instead of silently labeling everything one_off" do
    rows = [ { "description" => "X", "amount_cents" => 100, "direction" => "out", "signals" => [] } ]
    assert_raises(Imports::ParseError) do
      Imports::RecurringClassifier.call(rows, client: FakeClient.new(nil))
    end
  end

  test "builds income + fixed + installment + subscription proposals, excludes sweep interest" do
    import = build_with(statement_extraction, LABELS)
    kinds = import.proposals.map { it["kind"] }
    assert_includes kinds, "bank_account"
    assert_equal 1, import.proposals.count { it["kind"] == "income" }
    assert_equal 3, import.proposals.count { it["kind"] == "commitment" }
    # REMUNERACAO APLICACAO (sweep_interest) is excluded pre-LLM — never a proposal.
    assert_not import.proposals.any? { it.dig("payload", "name").to_s.include?("REMUNERACAO") }
  end

  test "income is single-month capped (≤0.7, unchecked) and points at the account" do
    import = build_with(statement_extraction, LABELS)
    income = import.proposals.find { it["kind"] == "income" }
    assert_equal "Salário", income.dig("payload", "name")
    assert_equal 4_802_580, income.dig("payload", "amount_cents")
    assert_operator income["confidence"], :<=, 0.7
    assert_equal account_pid(import), income.dig("payload", "instrument_ref", "pid")
  end

  test "installment picks up presumed-paid parcels via a walked-back starts_on" do
    import = build_with(statement_extraction, LABELS)
    seguro = import.proposals.find { it.dig("payload", "commitment_kind") == "installment" }
    assert_equal 36, seguro.dig("payload", "installments_count")
    assert_equal 32_853, seguro.dig("payload", "amount_cents")
    # Parc 027/036 observed 05/06/2026 → starts 27 months earlier.
    assert_equal "2024-04-05", seguro.dig("payload", "starts_on")
    assert_operator seguro["confidence"], :>=, 0.9
  end

  test "a deterministic-signal fixed bill is pre-checkable (≥0.9) despite a shy LLM score" do
    labels = LABELS.map { |l| l["id"] == 1 ? l.merge("confidence" => 0.4) : l }
    import = build_with(statement_extraction, labels)
    copel = import.proposals.find { it.dig("payload", "name") == "Energia (Copel)" }
    assert_operator copel["confidence"], :>=, 0.9 # never overridden downward by the LLM
  end

  test "Reconciler suppresses an income that is really a cross-account self-transfer" do
    nubank    = extracted_with_income(4_802_580, "2026-06-04", "0260", "9100349-6") # a credit classified income
    santander = extracted_with_debit(4_802_580, "2026-06-05", "033", "1003172-6")   # the matching debit

    Imports::Reconciler.call(@user.account)

    income = nubank.reload.proposals.find { it["kind"] == "income" }
    assert_equal "rejected", income["state"] # paired debit within skew → excluded
    assert santander.reload # (touched only for its rows)
  end

  test "Reconciler leaves a genuine income (no matching debit) alone" do
    nubank = extracted_with_income(4_802_580, "2026-06-04", "0260", "9100349-6")
    Imports::Reconciler.call(@user.account)
    assert_equal "proposed", nubank.reload.proposals.find { it["kind"] == "income" }["state"]
  end

  private

  def build_with(extraction, labels)
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "n.ofx", content_type: "application/x-ofx")
    import.extraction = extraction
    import.save!
    stub_classifier(labels) { Imports::ProposalBuilder.call(import) }
    import.reload
  end

  def account_pid(import) = import.proposals.find { it["kind"] == "bank_account" }["pid"]

  def statement_extraction
    {
      "format" => "ofx", "doc_kind" => "bank_statement",
      "meta" => { "acct" => { "bank_id" => "0260", "branch_id" => "1", "acct_id" => "9100349-6" },
                  "period_end" => "2026-06-30", "ledger_balance_cents" => 357_625, "ledger_balance_as_of" => "2026-06-30" },
      "rows" => [
        row("2026-06-03", "PIX RECEBIDO SOMA COOP MATRIZ", 4_802_580, "in"),
        row("2026-06-22", "DEBITO AUT. COPEL", 31_741, "out"),
        row("2026-06-05", "MENSALIDADE DE SEGURO Parc 027/036 INCENDIO RES", 32_853, "out"),
        row("2026-06-15", "NETFLIX.COM", 3_990, "out"),
        row("2026-06-10", "REMUNERACAO APLICACAO AUTOMATICA", 7, "in")
      ]
    }
  end

  def row(date, description, amount_cents, direction)
    { "date" => date, "description" => description, "amount_cents" => amount_cents,
      "direction" => direction, "external_id" => nil, "raw" => {}, "signals" => [] }
  end

  # An extracted import carrying one income proposal + the credit row it came from.
  def extracted_with_income(cents, date, bank_id, acct_id)
    import = new_extracted(bank_id, acct_id, [ row(date, "PIX RECEBIDO GRANDE", cents, "in") ])
    account = { "pid" => "acct#{bank_id}", "kind" => "bank_account", "state" => "proposed", "confidence" => 0.9, "payload" => {} }
    income = { "pid" => "inc#{bank_id}", "kind" => "income", "state" => "proposed", "confidence" => 0.7,
               "payload" => { "amount_cents" => cents }, "evidence" => [ { "date" => date, "amount_cents" => cents } ] }
    import.update!(proposals: [ account, income ])
    import
  end

  def extracted_with_debit(cents, date, bank_id, acct_id)
    new_extracted(bank_id, acct_id, [ row(date, "PIX ENVIADO GRANDE", cents, "out") ]).tap { it.update!(proposals: []) }
  end

  def new_extracted(bank_id, acct_id, rows)
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx", status: "uploaded")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")), filename: "x.ofx", content_type: "application/x-ofx")
    import.save!
    import.update!(status: "extracted", extraction: { "rows" => rows, "meta" => { "acct" => { "bank_id" => bank_id, "acct_id" => acct_id } } })
    import
  end
end
