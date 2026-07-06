require "test_helper"
require_relative "../../test_helpers/import_extraction_fixtures"

class Imports::ProposalBuilderTest < ActiveSupport::TestCase
  include ImportExtractionFixtures

  setup { @user = users(:confirmed) }

  test "builds a bank_account proposal with Nubank identity and the balance anchor" do
    import = build!(ofx_import)

    assert_equal "extracted", import.status
    assert_equal "bank_statement", import.kind
    assert_equal "260", import.institution.code
    assert_equal "0260", import.fingerprint["bank_code"]
    assert_equal 357_625, import.fingerprint["ledger_balance_cents"]

    account = import.proposals.find { it["kind"] == "bank_account" }
    assert_equal "proposed", account["state"]
    assert_operator account["confidence"], :>=, 0.8
    assert_equal 357_625, account.dig("payload", "balance_cents")
    assert_equal "2026-06-30", account.dig("payload", "balance_as_of")
    assert_equal "9100349-6", account.dig("payload", "account_number")
  end

  test "the DEBITO AUT. row becomes a fixed commitment on the account (0.9 signal floor)" do
    import = build!(ofx_import)
    copel = import.proposals.find { it["kind"] == "commitment" }
    assert_equal "fixed", copel.dig("payload", "commitment_kind")
    assert_operator copel["confidence"], :>=, 0.9 # debito_automatico floor
    assert_equal({ "pid" => account_pid(import) }, copel.dig("payload", "instrument_ref"))
  end

  test "resolves an unknown COMPE code to Outro" do
    import = ofx_import
    import.file.blob.update!(filename: "doc.ofx") # neutral name — no filename hint either
    import.update!(extraction: import.extraction.deep_merge("meta" => { "acct" => { "bank_id" => "9999" } }))
    build!(import)
    assert_equal Institution::OTHER_CODE, import.reload.institution.code
  end

  test "falls back to the uploaded filename when the document names no institution" do
    extraction = fatura_extraction.tap { it["meta"].delete("institution_name") }
    import = pdf_import(extraction)
    import.file.blob.update!(filename: "Nubank_2026-07-10.pdf")
    build!(import)
    assert_equal "260", import.reload.institution.code
  end

  test "pids are deterministic across re-runs (idempotent)" do
    import = build!(ofx_import)
    first = import.proposals.map { it["pid"] }
    build!(import)
    assert_equal first, import.reload.proposals.map { it["pid"] }
  end

  test "a CSV with no account header yields no proposals (no instrument to attach to)" do
    csv = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "csv")
    csv.file.attach(io: File.open(file_fixture("imports/sample.csv")), filename: "s.csv", content_type: "text/csv")
    csv.extraction = Imports::CsvParser.call(file_fixture("imports/sample.csv").read)
    csv.save!
    build!(csv)
    assert_empty csv.reload.proposals
  end

  test "a fatura yields ONE credit_card proposal (six plastics collapse to one card)" do
    import = build!(pdf_import(fatura_extraction))

    assert_equal "card_bill", import.kind
    assert_equal "033", import.institution.code
    cards = import.proposals.select { it["kind"] == "credit_card" }
    assert_equal 1, cards.size
    payload = cards.first["payload"]
    assert_equal "8431", payload["last4"]
    assert_equal 10, payload["bill_due_day"]
    assert_equal 7, payload["closing_offset_days"]
    assert_equal 13_259_000, payload["credit_limit_cents"]
  end

  test "an extrato PDF yields a bank_account with the closing balance and COMPE institution" do
    import = build!(pdf_import(extrato_extraction))
    account = import.proposals.find { it["kind"] == "bank_account" }
    assert_equal "033", import.institution.code
    assert_equal 322_179, account.dig("payload", "balance_cents")
    assert_equal "01003172-6", account.dig("payload", "account_number")
  end

  private

  def build!(import, labels = [])
    stub_classifier(labels) { Imports::ProposalBuilder.call(import) }
    import.reload
  end

  def account_pid(import)
    import.proposals.find { it["kind"] == "bank_account" }["pid"]
  end

  def pdf_import(extraction)
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "pdf")
    import.file.attach(io: File.open(file_fixture("imports/statement.pdf")),
                       filename: "doc.pdf", content_type: "application/pdf")
    import.extraction = extraction
    import.save!
    import
  end

  def ofx_import
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "nubank.ofx", content_type: "application/x-ofx")
    import.extraction = Imports::OfxParser.call(file_fixture("imports/nubank.ofx").read)
    import.save!
    import
  end
end
