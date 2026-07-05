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
    assert_difference -> { @user.credit_cards.count }, 1 do
      Imports::Apply.call(user: @user, accepted: { card_import.id => [ pid ] })
    end
    card = @user.credit_cards.last
    assert_equal "8431", card.last4
    assert_equal 10, card.bill_due_day
    assert_equal 7, card.closing_offset_days
    assert card.billing_configured?
    assert_equal "applied", card_import.reload.status
  end

  test "creates a BankAccount with the balance anchored to the period end, not Time.current" do
    travel_to Time.zone.local(2026, 7, 5, 12) do
      result = Imports::Apply.call(user: @user, accepted: { @import.id => [ @pid ] })

      account = @user.bank_accounts.last
      assert_equal 357625, account.balance_cents
      assert_equal Date.new(2026, 6, 30), account.balance_anchored_at.to_date # stamp override held
      assert_equal 1, result.created["bank_account"]
      assert_equal "applied", @import.reload.status
      assert_equal "applied", @import.proposals.first["state"]
      assert_equal account.to_global_id.to_s, @import.proposals.first["record"]
    end
  end

  test "is idempotent on replay — zero new records, proposal stays applied" do
    Imports::Apply.call(user: @user, accepted: { @import.id => [ @pid ] })
    gid = @import.reload.proposals.first["record"]
    assert_no_difference -> { @user.bank_accounts.count } do
      Imports::Apply.call(user: @user, accepted: { @import.id => [ @pid ] })
    end
    assert_equal "applied", @import.reload.proposals.first["state"]
    assert_equal gid, @import.proposals.first["record"] # same account, not re-created
  end

  test "matches a pre-existing account (normalized number) instead of duplicating" do
    @user.bank_accounts.create!(institution: Institution.find_by(code: "260"), account_number: "09100349-6")
    assert_no_difference -> { @user.bank_accounts.count } do
      result = Imports::Apply.call(user: @user, accepted: { @import.id => [ @pid ] })
      assert_equal 1, result.skipped
    end
    assert_equal "applied", @import.reload.proposals.first["state"]
  end

  test "unchecked proposals stay proposed and the import stays extracted" do
    Imports::Apply.call(user: @user, accepted: { @import.id => [] })
    assert_equal "extracted", @import.reload.status
    assert_equal "proposed", @import.proposals.first["state"]
  end

  test "a cross-user import id never loads" do
    other = User.create!(email_address: "x@example.com", password: "password123")
    assert_no_difference -> { BankAccount.count } do
      Imports::Apply.call(user: other, accepted: { @import.id => [ @pid ] })
    end
    assert_equal "extracted", @import.reload.status
  end

  private

  def pdf_card_import
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "pdf")
    import.file.attach(io: File.open(file_fixture("imports/statement.pdf")),
                       filename: "fatura.pdf", content_type: "application/pdf")
    import.extraction = fatura_extraction
    import.save!
    Imports::ProposalBuilder.call(import)
    import.reload
  end

  def extracted_import
    import = @user.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")),
                       filename: "nubank.ofx", content_type: "application/x-ofx")
    import.extraction = Imports::OfxParser.call(file_fixture("imports/nubank.ofx").read)
    import.save!
    Imports::ProposalBuilder.call(import)
    import.reload
  end
end
