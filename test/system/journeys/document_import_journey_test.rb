require "test_helpers/e2e/browser_case"

# WEB-IMP-01 browser residue (.plans/e2e/05 §4): the review form + apply interaction and the
# status Turbo Frame. The extraction math + the upload→extract async path are owned by
# document_imports_controller_test.rb (Lane P, in-process, canned); here we drive the
# browser-only surface off a SEEDED extracted import (deterministic — no async job).
class JourneysDocumentImportTest < E2E::BrowserCase
  test "review a proposal and apply it into the ledger" do
    s = E2E::Scenario.build(:solo_basic)
    import = seed_import(s.account, status: "extracted")
    before = s.account.bank_accounts.kept.count

    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit review_document_imports_path

    assert_text "Nubank"   # the proposal rendered (the acct1 checkbox is pre-checked, conf 0.9)
    click_button I18n.t("document_imports.review.create_selected")

    assert_current_path bank_accounts_path   # wait for the apply redirect before touching the DB
    assert_equal before + 1, s.account.bank_accounts.kept.count, "the proposal became a real bank account"
    assert import.reload.applied?
  end

  test "the status frame shows the reading spinner while an import is processing" do
    s = E2E::Scenario.build(:solo_basic)
    seed_import(s.account, status: "processing")

    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit status_document_imports_path

    assert_text I18n.t("document_imports.status.processing")
  end

  private

  def seed_import(account, status:)
    import = account.document_imports.new(checksum: SecureRandom.hex, source_format: "ofx", status: "uploaded")
    import.file.attach(io: File.open(file_fixture("imports/nubank.ofx")), filename: "n.ofx",
                       content_type: "application/x-ofx")
    import.save!
    proposals = status == "extracted" ? [
      { "pid" => "acct1", "kind" => "bank_account", "state" => "proposed", "confidence" => 0.9,
        "payload" => { "institution_code" => "260", "balance_cents" => 357_625 },
        "evidence" => [ { "kind" => "bank_statement", "date" => "2026-06-30", "amount_cents" => 357_625 } ] }
    ] : []
    import.update!(status: status, proposals: proposals)
    import
  end
end
