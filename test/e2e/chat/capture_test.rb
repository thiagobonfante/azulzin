require "test_helpers/e2e/pipeline_case"

# AP-CHAT (.plans/mobile/08 §6): in-app chat capture — the SAME pipeline as WhatsApp, the
# SAME reply copy, delivered as chat bubbles instead of sidecar sends. Inbound is the real
# signed-cookie composer POST; replies are asserted as outbound ChatMessage bodies pinned
# to the identical I18n keys the WA goldens pin — and the sidecar must stay silent.
class E2E::ChatCaptureTest < E2E::PipelineCase
  # AP-CHAT-01 — text expense → posted assigned, exact centavos, WA-identical reply bubble
  test "text expense posts with exact centavos and replies with the WA golden as a bubble" do
    s = sign_in_scenario(:solo_basic)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                                     method: "debito", instrument: "itau")) do
      chat_say(s, "padaria sol 54,90 no itaú")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 5_490, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal "whatsapp_text", txn.source   # same pipeline, same provenance tagging

    assert_chat_reply s, equals: I18n.t("whatsapp.replies.posted_account",
                                        amount: brl(5_490), instrument: s.itau.display_name,
                                        locale: :"pt-BR")
    assert_empty fake_sidecar.messages, "a chat reply must never reach the sidecar"
  end

  # AP-CHAT-02 — audio → canned STT transcript → same money path as text
  test "audio message transcribes and posts exactly like text" do
    s = sign_in_scenario(:solo_basic)

    with_canned_ai(transcript: "padaria sol 54,90 no itaú",
                   extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                                     method: "debito", instrument: "itau",
                                                     modality: "audio")) do
      chat_say(s, nil, media: fixture_file_upload("audio.webm", "audio/webm"))
      drain_jobs!
    end

    msg = ChatMessage.where(user: s.owner, direction: "inbound").sole
    assert_equal "audio", msg.message_type
    assert_equal "padaria sol 54,90 no itaú", msg.reload.transcription

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 5_490, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_chat_reply s, equals: I18n.t("whatsapp.replies.posted_account",
                                        amount: brl(5_490), instrument: s.itau.display_name,
                                        locale: :"pt-BR")
  end

  # AP-CHAT-03 — receipt image → vision path → auto-record + receipt blob + ai provenance
  test "receipt photo runs the vision path, attaches the receipt and keeps provenance" do
    s = sign_in_scenario(:solo_basic)

    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Mercado Nota", method: "debito",
                                    instrument: "itau", category: "Mercado", modality: "image")
    with_canned_ai(receipt: receipt) do
      chat_say(s, nil, media: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 8_750, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal "whatsapp_receipt", txn.source
    assert_equal s.category("Mercado").id, txn.category_id
    assert_equal "ai", txn.category_source            # closed-set piggyback — never "user"
    assert txn.receipt.attached?, "the chat photo must ride onto the transaction"
    msg = ChatMessage.where(user: s.owner, direction: "inbound").sole
    assert_equal msg.media.blob.id, txn.receipt.blob.id, "same blob, no byte copy"

    assert_chat_reply s, equals: I18n.t("whatsapp.replies.posted_account_categorized",
                                        amount: brl(8_750), instrument: s.itau.display_name,
                                        category: s.category("Mercado").name, locale: :"pt-BR")
  end

  # AP-CHAT-04 — several expenses in one message → one batch reply bubble
  test "a multi-expense message posts every row and answers with ONE batch bubble" do
    s = sign_in_scenario(:solo_basic)

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupas",  method: "debito", instrument: "itau" },
      { cents: 1_122,  merchant: "pedágio", method: "debito", instrument: "itau" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = chat_say(s, "197 roupas, 11,22 pedágio no itaú")
      drain_jobs!
    end

    txns = Whatsapp::MultiExpenseHandler.batch_rows(s.account, msg.wa_message_id)
    assert_equal [ 19_700, 1_122 ], txns.map(&:amount_cents)
    assert txns.all?(&:posted?)

    lines = [
      I18n.t("whatsapp.replies.multi_line_posted", amount: brl(19_700), label: "roupas",
             instrument: s.itau.display_name, locale: :"pt-BR"),
      I18n.t("whatsapp.replies.multi_line_posted", amount: brl(1_122), label: "pedágio",
             instrument: s.itau.display_name, locale: :"pt-BR")
    ]
    assert_equal 1, outbound_bubbles(s).count, "batch answers with a single bubble"
    assert_chat_reply s, equals: I18n.t("whatsapp.replies.multi_posted", count: 2,
                                        lines: lines.join("\n"), locale: :"pt-BR")
  end

  # AP-CHAT-05 — edit_last corrects the row and acks; the WA twin pins the same key
  test "an edit_last follow-up corrects the posted row and acks in the thread" do
    s = sign_in_scenario(:solo_basic)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "posto",
                                                     method: "debito", instrument: "itau")) do
      chat_say(s, "posto 50 no itaú")
      drain_jobs!
    end
    txn = s.account.transactions.sole
    assert_equal 5_000, txn.amount_cents

    with_canned_ai(extraction: E2E::CannedAI.edit_last(field_hint: "amount", cents: 5_500)) do
      chat_say(s, "na verdade foi 55")
      drain_jobs!
    end

    assert_equal 5_500, txn.reload.amount_cents
    assert_chat_reply s, equals: I18n.t("whatsapp.replies.edited",
                                        amount: brl(5_500), instrument: s.itau.display_name,
                                        locale: :"pt-BR")
  end

  # AP-CHAT-06 — AI failure → fail_and_tell degrade bubble, nothing posted
  test "an AI outage degrades to the fail-and-tell bubble and posts nothing" do
    s = sign_in_scenario(:solo_basic)

    msg = nil
    Whatsapp::Extractor.stub(:from_text, ->(*) { raise OpenRouterClient::Error, "OpenRouter 502" }) do
      msg = chat_say(s, "padaria 20")
      drain_jobs!
    end

    assert_equal "failed", msg.reload.status
    assert_empty s.account.transactions
    assert_chat_reply s, equals: I18n.t("whatsapp.replies.processing_failed", locale: :"pt-BR")
    assert_empty fake_sidecar.messages, "the degrade reply stays in the thread"
  end

  # AP-CHAT-07 — tenancy (couple): sender attribution + per-user thread
  test "a member's chat expense posts to the shared account with their attribution, thread stays per-user" do
    s = E2E::Scenario.build(:couple)
    sign_in(s.partner)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 3_200, merchant: "farmácia",
                                                     method: "debito", instrument: "itau")) do
      chat_say(s, "farmácia 32", as: s.partner)
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal s.partner, txn.created_by, "attribution is the SENDER, not the owner"
    assert_equal s.account, txn.account

    assert_equal 1, outbound_bubbles(s, user: s.partner).count
    assert_empty ChatMessage.where(user: s.owner), "the owner's thread never sees the partner's conversation"
  end

  private

  def sign_in_scenario(pack, **)
    s = E2E::Scenario.build(pack)
    sign_in(s.owner)
    s
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: E2E::Scenario::PASSWORD }
    assert_response :redirect
  end

  # The composer POST (the same signed-cookie request the web/native form makes).
  # Plain-form semantics: the HTML fallback answers with a redirect back to the thread.
  def chat_say(s, body, media: nil, as: nil)
    params = { chat_message: { body: body }.compact }
    params[:chat_message][:media] = media if media
    post chat_messages_path, params: params
    assert_redirected_to chat_path
    ChatMessage.where(user: as || s.owner, direction: "inbound").order(:id).last
  end

  def outbound_bubbles(s, user: nil)
    ChatMessage.where(user: user || s.owner, direction: "outbound").order(:id)
  end

  def assert_chat_reply(s, equals:, user: nil)
    bubble = outbound_bubbles(s, user: user).last
    assert bubble, "expected an outbound chat bubble; none was created"
    assert_equal equals, bubble.body
  end
end
