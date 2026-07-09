require "test_helpers/e2e/pipeline_case"

# Phase 0 walking skeleton (WA-CAP-01 shape): real webhook envelope in → real job pipeline →
# real outbound HTTP captured by the fake sidecar, with exact money in the reply.
# Proves the harness before anything is built on it. See .plans/e2e/06 Phase 0.
class E2E::CaptureSmokeTest < E2E::PipelineCase
  test "inject expense → posted with exact cents → golden-shaped reply over real HTTP" do
    user = users(:confirmed)
    user.update!(whatsapp_id: "5511900010001", phone_verified_at: Time.current, phone: "5511900010001")
    jid  = "5511900010001@c.us"
    card = CreditCard.create!(account: user.account, institution: Institution.find_by(code: "260"))

    extraction = E2E::CannedAI.expense(cents: 5_490, merchant: "mercado pão",
                                       instrument: "cartão Nubank")
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(jid, "mercado pão 54,90 no cartão nubank")
      assert msg.present?, "webhook must persist the inbound WhatsappMessage"
      drain_jobs!
    end

    txn = user.account.transactions.sole
    assert txn.posted?
    assert_equal 5_490, txn.amount_cents
    assert_equal card, txn.credit_card
    assert_equal msg.wa_message_id, txn.source_message_id

    body = assert_wa_reply(jid, includes: [ "Lançado", "no cartão #{card.display_name}" ])
    assert_brl 5_490, body
    assert_equal body, WhatsappMessage.outbound.last.body, "outbound must be logged as a WhatsappMessage"
  end

  test "wrong bearer token → 401, nothing persisted, nothing enqueued" do
    assert_no_difference -> { WhatsappMessage.count } do
      post api_whatsapp_webhook_path,
           params: { event: "message_received", data: { from: "x@c.us", message_id_serialized: "t", type: "chat", body: "oi" } },
           as: :json, headers: { "Authorization" => "Bearer wrong" }
    end
    assert_response :unauthorized
    assert_empty enqueued_jobs
  end
end
