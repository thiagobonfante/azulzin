require "test_helpers/e2e/pipeline_case"

# WA-CAP core: expense capture postures, open asks, money exactness, media, rate cap,
# fallbacks (.plans/e2e/03 §2). All flows enter through the real webhook and reply through
# the fake sidecar's real HTTP capture.
class E2E::WhatsappCaptureTest < E2E::PipelineCase
  # WA-CAP-01 — with merchant memory feeding the category
  test "high confidence + memory category → posted assigned + categorized, exact reply" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    2.times do |i|
      s.expense(merchant: "Padaria Sol", category: "Mercado", instrument: s.itau,
                cents: 2_000 + i, on: Date.current - (i + 1))
    end

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "Padaria Sol",
                                                     method: "debito", instrument: "itau")) do
      wa_inject(s.jid, "padaria sol 54,90 no itaú")
      drain_jobs!
    end

    txn = s.account.transactions.where(source: "whatsapp_text").sole
    assert txn.posted?
    assert_equal 5_490, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal s.category("Mercado").id, txn.category_id
    assert_equal "memory", txn.category_source
    body = assert_wa_reply(s.jid, includes: [ "Lançado", "na conta #{s.itau.display_name}",
                                              s.category("Mercado").name ])
    assert_brl 5_490, body
  end

  # WA-CAP-02
  test "high confidence + undecidable instrument → posted UNASSIGNED" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "posto",
                                                     method: "desconhecido")) do
      wa_inject(s.jid, "gastei 50 no posto")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_nil txn.bank_account
    assert_nil txn.credit_card
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.posted_unassigned",
                                          amount: brl(5_000), locale: :"pt-BR"))
  end

  # WA-CAP-03
  test "confidence below the floor → parked in the review tray, never posted" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 3_000, merchant: "uns trecos",
                                                     confidence: 0.4, amount_confidence: 0.4)) do
      wa_inject(s.jid, "acho que gastei uns 30")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.pending_review?
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.parked", locale: :"pt-BR"))
  end

  # WA-CAP-04
  test "missing amount → asks quanto foi → the follow-up amount posts the SAME row" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: nil, merchant: "mercado",
                                                     instrument: "nubank").tap { |e| e.amount_raw = nil }) do
      wa_inject(s.jid, "comprei no nubank")
      drain_jobs!
    end
    ask = s.account.transactions.sole
    assert ask.needs_clarification?
    assert_equal "amount", ask.ask["slot"]
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.clarify_amount", locale: :"pt-BR"))

    wa_inject(s.jid, "137,90")   # open-ask routing: zero-LLM, no extractor stub needed
    drain_jobs!

    ask.reload
    assert ask.posted?
    assert_equal 13_790, ask.amount_cents
    assert_equal 1, s.account.transactions.count, "the follow-up must never mint a second row"
    assert_brl 13_790, assert_wa_reply(s.jid)
  end

  # WA-CAP-05
  test "an expired open ask is not slot-filled: the stale row stays, the reply starts fresh" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: nil, merchant: "loja").tap { |e| e.amount_raw = nil }) do
      wa_inject(s.jid, "comprei na loja")
      drain_jobs!
    end
    ask = s.account.transactions.sole

    travel 61.minutes
    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 13_790, merchant: nil,
                                                     method: "desconhecido")) do
      wa_inject(s.jid, "137,90")
      drain_jobs!
    end

    assert ask.reload.needs_clarification?, "the stale ask must stay unresolved"
    assert_equal 2, s.account.transactions.count, "the late reply starts a fresh pipeline"
  end

  # WA-CAP-06 — pt-BR money formats through the REAL Money.to_cents (ReplyRouter path)
  test "money formats parse to exact cents through the pipeline" do
    { "1.234,56" => 123_456, "1234,56" => 123_456, "R$ 15" => 1_500 }.each do |text, cents|
      s = E2E::Scenario.build(:solo_basic).wa_verified!
      with_canned_ai(extraction: E2E::CannedAI.expense(cents: nil, merchant: "loja").tap { |e| e.amount_raw = nil }) do
        wa_inject(s.jid, "comprei na loja")
        drain_jobs!
      end
      wa_inject(s.jid, text)
      drain_jobs!
      assert_equal cents, s.account.transactions.sole.reload.amount_cents,
                   "#{text.inspect} must parse to #{cents}"
    end
  end

  # WA-CAP-21
  test "audio: canned transcript is stored and the expense posts" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    media = { data: Base64.strict_encode64("fake-ogg-bytes"), mimetype: "audio/ogg", filename: "v.ogg" }

    msg = nil
    with_canned_ai(transcript: "mercado cinquenta e quatro e noventa",
                   extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "mercado", modality: "audio")) do
      msg = wa_inject(s.jid, "", type: "ptt", media: media)
      drain_jobs!
    end

    assert_equal "audio", msg.message_type
    assert_equal "mercado cinquenta e quatro e noventa", msg.reload.transcription
    assert_equal 5_490, s.account.transactions.sole.amount_cents
  end

  # WA-CAP-23 — a receipt whose amount MATCHES an already-posted card charge attaches to the
  # EXISTING row (Decider#reconcile_receipt: exact amount + same card + ±3 days): no duplicate,
  # the blob lands on the matched transaction, and the reply says "already recorded", not
  # "posted". Spec 03 §2; the duplicate-expense-from-receipt bug fixed in e2e-t3 §A1.
  test "image receipt matching an existing card charge attaches to it — no duplicate row" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    existing = s.expense(merchant: "Mercado Nota", category: "Outros", instrument: s.nubank_card,
                         cents: 8_750, on: Date.current)
    assert_equal 1, s.account.transactions.count

    bytes = File.binread(Rails.root.join("test/fixtures/files/receipt.jpg"))
    media = { data: Base64.strict_encode64(bytes), mimetype: "image/jpeg", filename: "receipt.jpg" }
    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Mercado Nota", method: "credito",
                                    instrument: "nubank", modality: "image")
    msg = nil
    with_canned_ai(receipt: receipt) do
      msg = wa_inject(s.jid, "", type: "image", media: media)
      drain_jobs!
    end

    assert_equal 1, s.account.transactions.count, "no duplicate row from a matching receipt"
    assert existing.reload.receipt.attached?, "the receipt reconciled onto the existing row"
    assert_equal msg.reload.media.blob.id, existing.receipt.blob.id, "same blob, no byte copy"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.receipt_matched_card",
                                          amount: brl(8_750),
                                          instrument: s.nubank_card.display_name,
                                          locale: :"pt-BR"))
  end

  # WA-CAP-24 — a receipt matching NOTHING creates the row and shares the SAME blob (survives
  # the WA media purge)
  test "image receipt: transaction created with the receipt attached to the same blob" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    bytes = File.binread(Rails.root.join("test/fixtures/files/receipt.jpg"))
    media = { data: Base64.strict_encode64(bytes), mimetype: "image/jpeg", filename: "receipt.jpg" }

    msg = nil
    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Mercado Nota", method: "debito",
                                    instrument: "itau", modality: "image")
    with_canned_ai(receipt: receipt) do
      msg = wa_inject(s.jid, "", type: "image", media: media)
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal 8_750, txn.amount_cents
    assert txn.receipt.attached?
    assert_equal msg.reload.media.blob.id, txn.receipt.blob.id, "receipt must reference the SAME blob"
  end

  # WA-CAP-22 — an STT failure degrades gracefully (fixed in e2e-t3 §A2; was: stuck at
  # "processing" with no reply): friendly reply, message marked failed, the audio row
  # survives, no transcript, and the money path is never entered. Spec 03 §2.
  test "STT failure: friendly reply, message marked failed, no transcript, no transaction" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    media = { data: Base64.strict_encode64("fake-ogg-bytes"), mimetype: "audio/ogg", filename: "v.ogg" }

    msg = nil
    Whatsapp::SttClient.stub(:transcribe, ->(*) { raise Whatsapp::SttClient::Error, "Groq STT 500" }) do
      msg = wa_inject(s.jid, "", type: "ptt", media: media)
      drain_jobs!
    end

    assert_equal "audio", msg.message_type
    msg.reload
    assert_equal "failed", msg.status
    assert_match(/\Astt_failed/, msg.error)
    assert_nil msg.transcription, "no transcript stored on failure"
    assert_empty s.account.transactions, "no half-written transaction"
    assert_wa_reply s.jid, equals: I18n.t("whatsapp.replies.stt_failed", locale: :"pt-BR")
  end

  # WA-CAP-25 — over the per-minute cap the message is stored but skipped (no AI, no reply)
  test "rate cap: the 21st message in a minute is stored as rate_limited, not processed" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 1_000, merchant: "loja",
                                                     method: "desconhecido")) do
      21.times do |i|
        wa_inject(s.jid, "loja 10 ##{i}")
        drain_jobs!
      end
    end

    statuses = WhatsappMessage.inbound.where(user: s.owner).order(:id).pluck(:status, :error)
    assert_equal 20, statuses.count { |st, _| st == "processed" }
    assert_equal [ "failed", "rate_limited" ], statuses.last
    assert_equal 20, s.account.transactions.count
    assert_equal 20, fake_sidecar.messages_to(s.jid).size, "the capped message gets no reply"
  end

  # WA-CAP-26 — the closing rule through the real pipeline
  test "card purchase on the closing day vs the day after lands one fatura apart" do
    s = E2E::Scenario.build(:cards_billing).wa_verified!
    close_day = s.nubank_card.bill_due_day - s.nubank_card.closing_offset_days
    prev = Date.current.beginning_of_month << 1
    on_close = prev + (close_day - 1)

    [ on_close, on_close + 1 ].each_with_index do |date, i|
      with_canned_ai(extraction: E2E::CannedAI.expense(cents: 9_900, merchant: "loja #{i}",
                                                       instrument: "nubank", occurred_on: date)) do
        wa_inject(s.jid, "loja #{i} 99 no nubank")
        drain_jobs!
      end
    end

    a, b = s.account.transactions.where(source: "whatsapp_text").order(:occurred_on).to_a
    assert_equal a.billing_month >> 1, b.billing_month,
                 "the day after closing must ride the NEXT fatura"
  end

  # WA-CAP-27
  test "gibberish with an amount parks; without an amount gets the help menu" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.base(intent: "other", intent_confidence: 0.3,
                                                  amount_cents: 4_200, merchant: nil,
                                                  payment_method: "desconhecido",
                                                  field_confidence: { "amount" => 0.4 },
                                                  overall_confidence: 0.3)) do
      wa_inject(s.jid, "42 hmm")
      drain_jobs!
    end
    assert s.account.transactions.sole.pending_review?

    with_canned_ai(extraction: E2E::CannedAI.base(intent: "other", intent_confidence: 0.3,
                                                  payment_method: "desconhecido")) do
      wa_inject(s.jid, "bom dia")
      drain_jobs!
    end
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.help", locale: :"pt-BR"))
    assert_equal 1, s.account.transactions.count
  end

  # WA-CAP-28
  test "a mutating intent below the 0.75 floor never fires its verb" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.income(cents: 450_000, confidence: 0.5)) do
      wa_inject(s.jid, "recebi salário 4500 (talvez)")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.pending_review?, "below the floor the verb parks instead of posting income"
    assert_not_equal "income", txn.direction
  end
end
