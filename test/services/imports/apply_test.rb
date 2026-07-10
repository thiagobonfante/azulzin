require "test_helper"
require_relative "../../test_helpers/import_extraction_fixtures"

class Imports::ApplyTest < ActiveSupport::TestCase
  include ImportExtractionFixtures

  setup do
    @user   = users(:confirmed)
    @import = extracted_import
    @pid    = @import.proposals.first["pid"]
  end

  test "creates ONE CreditCard, billing configured, without a billing recompute" do
    card_import = pdf_card_import
    pid = card_import.proposals.first["pid"]
    assert_difference -> { @user.account.credit_cards.count }, 1 do
      Imports::Apply.call(account: @user.account, accepted: { card_import.id => [ pid ] })
    end
    card = @user.account.credit_cards.last
    assert_equal "8431", card.last4
    assert_equal 10, card.bill_due_day
    assert_equal 7, card.closing_offset_days
    assert card.billing_configured?
    assert_equal "applied", card_import.reload.status
  end

  test "creates a BankAccount with the balance anchored to the period end, not Time.current" do
    travel_to Time.zone.local(2026, 7, 5, 12) do
      result = Imports::Apply.call(account: @user.account, accepted: { @import.id => [ @pid ] })

      account = @user.account.bank_accounts.last
      assert_equal 357625, account.balance_cents
      assert_equal Date.new(2026, 6, 30), account.balance_anchored_at.to_date # stamp override held
      assert_equal 1, result.created["bank_account"]
      assert_equal "applied", @import.reload.status
      assert_equal "applied", @import.proposals.first["state"]
      assert_equal account.to_global_id.to_s, @import.proposals.first["record"]
    end
  end

  test "is idempotent on replay — zero new records, proposal stays applied" do
    Imports::Apply.call(account: @user.account, accepted: { @import.id => [ @pid ] })
    gid = @import.reload.proposals.first["record"]
    assert_no_difference -> { @user.account.bank_accounts.count } do
      Imports::Apply.call(account: @user.account, accepted: { @import.id => [ @pid ] })
    end
    assert_equal "applied", @import.reload.proposals.first["state"]
    assert_equal gid, @import.proposals.first["record"] # same account, not re-created
  end

  test "matches a pre-existing account (normalized number) instead of duplicating" do
    @user.account.bank_accounts.create!(institution: Institution.find_by(code: "260"), account_number: "09100349-6")
    assert_no_difference -> { @user.account.bank_accounts.count } do
      result = Imports::Apply.call(account: @user.account, accepted: { @import.id => [ @pid ] })
      assert_equal 1, result.skipped
    end
    assert_equal "applied", @import.reload.proposals.first["state"]
  end

  test "a pid shared across imports (multi-month uploads) creates one record, not two" do
    first, second = full_extracted_import, full_extracted_import
    accepted = { first.id => %w[acct-pid-1 cmt-pid-1], second.id => %w[acct-pid-1 cmt-pid-1] }
    result = nil
    assert_difference -> { @user.account.commitments.count } => 1, -> { @user.account.bank_accounts.count } => 1 do
      result = Imports::Apply.call(account: @user.account, accepted: accepted)
    end
    assert_equal 1, result.created["commitment"]
    assert_equal 2, result.skipped # second import's copies bound to the first's records
    second_copy = second.reload.proposals.find { it["pid"] == "cmt-pid-1" }
    assert_equal "applied", second_copy["state"]
    assert_equal @user.account.commitments.last.to_global_id.to_s, second_copy["record"]
  end

  test "unchecked proposals stay proposed and the import stays extracted" do
    Imports::Apply.call(account: @user.account, accepted: { @import.id => [] })
    assert_equal "extracted", @import.reload.status
    assert_equal "proposed", @import.proposals.first["state"]
  end

  test "a cross-user import id never loads" do
    other = User.create!(email_address: "x@example.com", password: "password123")
    Accounts::Bootstrap.call(other)
    assert_no_difference -> { BankAccount.count } do
      Imports::Apply.call(account: other.account, accepted: { @import.id => [ @pid ] })
    end
    assert_equal "extracted", @import.reload.status
  end

  test "topological apply: instruments first, then a commitment + income resolve the new account" do
    import = full_extracted_import
    accepted = { import.id => import.proposals.map { it["pid"] } }

    travel_to(Time.zone.local(2026, 7, 5)) { Imports::Apply.call(account: @user.account, accepted: accepted) }
    @user.reload

    assert_equal 1, @user.account.bank_accounts.count
    assert_equal 1, @user.account.incomes.count
    assert_equal 1, @user.account.commitments.count
    commitment = @user.account.commitments.first
    assert_equal @user.account.bank_accounts.first, commitment.bank_account
    assert_equal "import", commitment.source
    assert_nil commitment.source_message_id
    assert_equal @user.account.bank_accounts.first, @user.account.incomes.first.bank_account
    assert_equal "applied", import.reload.status
  end

  test "a dependent whose instrument was left unchecked fails with missing_instrument" do
    import = full_extracted_import
    income_pid = import.proposals.find { it["kind"] == "income" }["pid"]

    result = Imports::Apply.call(account: @user.account, accepted: { import.id => [ income_pid ] })

    assert_equal 0, @user.account.incomes.count
    failed = import.reload.proposals.find { it["kind"] == "income" }
    assert_equal "failed", failed["state"]
    assert_includes failed["error"], I18n.t("imports.apply.errors.missing_instrument")
    assert_equal 1, result.failed.size
  end

  private

  def full_extracted_import
    ref = { "pid" => "acct-pid-1" }
    account = { "pid" => "acct-pid-1", "kind" => "bank_account", "state" => "proposed", "confidence" => 0.9,
                "payload" => { "institution_code" => "260", "kind" => "checking", "agency" => "1",
                               "account_number" => "9100349-6", "balance_cents" => 357_625, "balance_as_of" => "2026-06-30" } }
    income = { "pid" => "inc-pid-1", "kind" => "income", "state" => "proposed", "confidence" => 0.7,
               "payload" => { "name" => "Salário", "amount_cents" => 4_802_580, "schedule_kind" => "fixed_day",
                              "schedule_day" => 3, "instrument_ref" => ref }, "evidence" => [] }
    commitment = { "pid" => "cmt-pid-1", "kind" => "commitment", "state" => "proposed", "confidence" => 0.9,
                   "payload" => { "commitment_kind" => "fixed", "name" => "Copel", "amount_cents" => 31_741,
                                  "schedule_kind" => "fixed_day", "schedule_day" => 22, "starts_on" => "2026-06-22",
                                  "instrument_ref" => ref }, "evidence" => [] }
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx", status: "uploaded")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")), filename: "f.ofx", content_type: "application/x-ofx")
    import.save!
    import.update!(status: "extracted", proposals: [ account, income, commitment ])
    import
  end

  def pdf_card_import
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "pdf")
    import.file.attach(io: File.open(file_fixture("imports/statement.pdf")),
                       filename: "fatura.pdf", content_type: "application/pdf")
    import.extraction = fatura_extraction
    import.save!
    stub_classifier { Imports::ProposalBuilder.call(import) }
    focus_on(import.reload, "credit_card")
  end

  # These apply tests target the instrument; drop the sibling commitment proposals so status
  # transitions are unambiguous (full topological apply is covered in the recurring/e2e tests).
  def focus_on(import, kind)
    import.update!(proposals: import.proposals.select { it["kind"] == kind })
    import
  end

  def extracted_import
    import = @user.account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "nubank.ofx", content_type: "application/x-ofx")
    import.extraction = Imports::OfxParser.call(file_fixture("imports/nubank.ofx").read)
    import.save!
    stub_classifier { Imports::ProposalBuilder.call(import) }
    focus_on(import.reload, "bank_account")
  end
end
