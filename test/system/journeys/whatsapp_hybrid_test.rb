require "test_helpers/e2e/browser_case"

# HYB: WhatsApp ↔ web consistency — what WA does, the browser shows, to the centavo
# (.plans/e2e/03 §5).
class JourneysWhatsappHybridTest < E2E::BrowserCase
  include ActionView::RecordIdentifier

  # HYB-02
  test "a WA-parked expense lands in the review tray and confirms into the ledger" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit transactions_path

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 3_000, merchant: "Uns Trecos",
                                                     confidence: 0.4, amount_confidence: 0.4)) do
      wa_inject(s.jid, "acho que gastei uns 30")
      drain_jobs!
    end
    txn = s.account.transactions.sole
    assert txn.pending_review?

    visit transactions_path
    assert_text I18n.t("transactions.tray.title")
    within "##{dom_id(txn)}" do
      assert_selector "input[value='Uns Trecos']"   # merchant arrives pre-filled in the tray form
      find("button[data-method='debito']").click    # review the guess: débito → lone account auto-selects
      assert_selector "[data-entry-instrument-target='display']", text: s.itau.display_name
      click_button I18n.t("transactions.row.confirm")
    end

    assert_no_text I18n.t("transactions.tray.title")   # the tray disappears once empty
    assert txn.reload.posted?

    visit transactions_path   # fresh render: the posted row and month figures agree
    assert_text brl(3_000)
  end

  # HYB-04
  test "apaga o último removes the row from the ledger and recomputes the month" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                                     method: "debito", instrument: "itau")) do
      wa_inject_rack(s.jid, "padaria sol 54,90")
      drain_jobs!
    end
    txn = s.account.transactions.sole

    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit transactions_path
    assert_text "Padaria Sol"

    wa_inject(s.jid, "apaga o último")
    drain_jobs!
    assert txn.reload.rejected?

    visit transactions_path
    assert_no_text "Padaria Sol"   # the reversed row must leave the ledger
  end

  private

  # Before any page is visited the Capybara server isn't up; go through the rack route the
  # pipeline lane uses (same controller, same auth).
  def wa_inject_rack(jid, body)
    id = "fake_in_#{E2E::Seq.next}"
    Net::HTTP.post(URI("#{fake_sidecar_rack_base}/api/whatsapp/webhook"),
                   { event: "message_received",
                     data: { from: jid, message_id_serialized: id, type: "chat", body: body } }.to_json,
                   "Content-Type" => "application/json", "Authorization" => "Bearer #{E2E::TOKEN}")
    WhatsappMessage.find_by(wa_message_id: id)
  end

  def fake_sidecar_rack_base
    visit root_path unless Capybara.current_session.server
    server = Capybara.current_session.server
    "http://#{server.host}:#{server.port}"
  end
end
