require "test_helpers/e2e/browser_case"

# WEB-CH-01 (.plans/mobile/08 §6): the product moment — type an expense, the inbound bubble
# appears, the azulzinho reply bubble arrives LIVE over Action Cable, the row is in Movimentos.
class JourneysChatCaptureTest < E2E::BrowserCase
  # cable.yml's test adapter buffers broadcasts for assert_broadcasts and never delivers to
  # real subscribers — the reply bubble would never reach the browser. Swap in the
  # in-process async adapter for this journey, restore after (server.restart drops the
  # pubsub so the next test re-reads the config).
  setup do
    @cable_was = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
  end

  teardown do
    ActionCable.server.config.cable = @cable_was
    ActionCable.server.restart
  end

  test "WEB-CH-01: typed expense → inbound bubble → live reply bubble → row in Movimentos" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit chat_path
    assert_text I18n.t("chat.show.empty")

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                                     method: "debito", instrument: "itau")) do
      fill_in "chat_message[body]", with: "padaria sol 54,90 no itaú"
      click_button I18n.t("chat.composer.send")
      assert_selector "#chat_messages .chat-end", text: "padaria sol 54,90"   # inbound bubble

      drain_jobs!   # pipeline runs → reply bubble broadcast over the swapped-in async cable
      assert_selector "#chat_messages .chat-start", text: "Lançado"   # bubble BEFORE the DB
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 5_490, txn.amount_cents

    visit transactions_path
    assert_text "Padaria Sol"
    assert_brl 5_490, find("#ledger_list").text
  end
end
