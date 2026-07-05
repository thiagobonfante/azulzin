require "test_helper"

class Imports::ProposalBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @import = ofx_import
  end

  test "builds one bank_account proposal with Nubank identity and the balance anchor" do
    Imports::ProposalBuilder.call(@import)
    @import.reload

    assert_equal "extracted", @import.status
    assert_equal "bank_statement", @import.kind
    assert_equal "260", @import.institution.code
    assert_equal "0260", @import.fingerprint["bank_code"]
    assert_equal 357625, @import.fingerprint["ledger_balance_cents"]
    assert_equal "2026-06-30", @import.fingerprint["ledger_balance_as_of"]

    assert_equal 1, @import.proposals.size
    proposal = @import.proposals.first
    assert_equal "bank_account", proposal["kind"]
    assert_equal "proposed", proposal["state"]
    assert_operator proposal["confidence"], :>=, 0.8
    assert_equal 357625, proposal.dig("payload", "balance_cents")
    assert_equal "2026-06-30", proposal.dig("payload", "balance_as_of")
    assert_equal "9100349-6", proposal.dig("payload", "account_number")
    assert_equal "checking", proposal.dig("payload", "kind")
  end

  test "resolves an unknown COMPE code to Outro" do
    @import.update!(extraction: @import.extraction.deep_merge("meta" => { "acct" => { "bank_id" => "9999" } }))
    Imports::ProposalBuilder.call(@import)
    assert_equal Institution::OTHER_CODE, @import.reload.institution.code
  end

  test "pids are deterministic across re-runs (idempotent)" do
    Imports::ProposalBuilder.call(@import)
    first = @import.reload.proposals.map { it["pid"] }
    Imports::ProposalBuilder.call(@import)
    assert_equal first, @import.reload.proposals.map { it["pid"] }
  end

  test "a CSV with no account header yields no bank_account proposal" do
    csv = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "csv")
    csv.file.attach(io: File.open(file_fixture("imports/sample.csv")), filename: "s.csv", content_type: "text/csv")
    csv.extraction = Imports::CsvParser.call(file_fixture("imports/sample.csv").read)
    csv.save!
    Imports::ProposalBuilder.call(csv)
    assert_empty csv.reload.proposals
    assert_equal "extracted", csv.status
  end

  private

  def ofx_import
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "nubank.ofx", content_type: "application/x-ofx")
    import.extraction = Imports::OfxParser.call(file_fixture("imports/nubank.ofx").read)
    import.save!
    import
  end
end
