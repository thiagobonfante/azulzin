require "test_helpers/e2e/browser_case"

# Phase 0 walking skeleton (HYB-01 shape): WhatsApp expense injected over a real socket to
# the running Puma server shows up in the browser ledger with the exact money string.
# See .plans/e2e/06 Phase 0.
class JourneysHybridSmokeTest < E2E::BrowserCase
  test "WA-injected expense appears on the transactions hub with exact money" do
    user = users(:confirmed)
    user.update!(name: "Ana", phone: "5511900010002", onboarded_at: Time.current,
                 whatsapp_id: "5511900010002", phone_verified_at: Time.current)
    jid = "5511900010002@c.us"
    conta = user.account.bank_accounts.create!(institution: Institution.find_by(code: "260"),
                                               nickname: "Conta Nubank")

    sign_in_via_ui(user, password: "password123")
    visit transactions_path

    extraction = E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                       method: "debito", instrument: "conta nubank")
    with_canned_ai(extraction: extraction) do
      wa_inject(jid, "padaria sol 54,90 no débito")
      drain_jobs!
    end
    assert_wa_reply(jid, includes: [ "na conta #{conta.display_name}" ])

    visit transactions_path
    assert_text "Padaria Sol"
    assert_text brl(5_490)
  end
end
