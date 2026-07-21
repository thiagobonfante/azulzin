require "test_helpers/e2e/pipeline_case"

# NA-CAP (.plans/mobile/05): share-to-app receipts. POST /captures rides the SAME vision
# pipeline as WhatsApp receipts, with NO reply channel — outcomes are transaction states
# only (posted row, unassigned state, review tray). The chat thread and the sidecar must
# both stay silent for every case.
class E2E::NativeCaptureTest < E2E::PipelineCase
  CAPTURE_HEADERS = { "X-Azulzin-Capture" => "1" }.freeze

  # NA-CAP-01 — image, high confidence, instrument matched → silent auto-record
  test "a shared receipt auto-records with exact centavos and provenance" do
    s = sign_in_scenario(:solo_basic)
    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Mercado Nota", method: "debito",
                                    instrument: "itau", category: "Mercado", modality: "image")
    with_canned_ai(receipt: receipt) do
      share!(file: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 8_750, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal "whatsapp_receipt", txn.source
    assert_equal s.category("Mercado").id, txn.category_id
    assert_equal "ai", txn.category_source
    assert txn.receipt.attached?, "the shared photo must ride onto the transaction"

    assert_silent_channels(s)
  end

  # NA-CAP-02 — low confidence → parked pending_review
  test "a low-confidence capture parks in the review tray" do
    s = sign_in_scenario(:solo_basic)
    receipt = E2E::CannedAI.expense(cents: 4_200, merchant: "Loja X", method: "debito",
                                    instrument: "itau", modality: "image",
                                    confidence: 0.3, amount_confidence: 0.3)
    with_canned_ai(receipt: receipt) do
      share!(file: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal "pending_review", txn.status
    assert_equal 4_200, txn.amount_cents
    assert_silent_channels(s)
  end

  # NA-CAP-03 — instrument unknown → posted unassigned ("toque para escolher")
  test "an instrument-less capture posts unassigned" do
    s = sign_in_scenario(:solo_basic)
    receipt = E2E::CannedAI.expense(cents: 2_990, merchant: "Padoca", method: nil,
                                    instrument: nil, modality: "image")
    with_canned_ai(receipt: receipt) do
      share!(file: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 2_990, txn.amount_cents
    assert_nil txn.bank_account
    assert_nil txn.credit_card
    assert_silent_channels(s)
  end

  # NA-CAP-04 — PDF share → document path → same outcome as 01
  test "a shared PDF records exactly like an image" do
    s = sign_in_scenario(:solo_basic)
    receipt = E2E::CannedAI.expense(cents: 12_000, merchant: "Restaurante Bom", method: "debito",
                                    instrument: "itau", modality: "image")
    with_canned_ai(receipt: receipt) do
      share!(file: fixture_file_upload("receipt.pdf", "application/pdf"))
      drain_jobs!
    end

    msg = CaptureMessage.where(user: s.owner).sole
    assert_equal "document", msg.message_type
    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal 12_000, txn.amount_cents
    assert txn.receipt.attached?
    assert_silent_channels(s)
  end

  # NA-CAP-05 — not_receipt → parked with the não-parece copy, never silently lost
  test "a not-receipt verdict parks a review row carrying the não-parece copy" do
    s = sign_in_scenario(:solo_basic)
    verdict = Whatsapp::Extraction.new(modality: "image", source: "whatsapp_receipt",
                                       raw: { "is_receipt" => false })
    with_canned_ai(receipt: verdict) do
      share!(file: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal "pending_review", txn.status
    assert_equal 0, txn.amount_cents
    assert_equal "Não parece um comprovante — confira a imagem", txn.merchant
    assert txn.receipt.attached?, "the image stays reviewable"
    assert_silent_channels(s)
  end

  # NA-CAP-06 — tenancy: the capture posts to the SENDER's shared account, their attribution
  test "a member's capture posts to the shared account with their attribution" do
    s = E2E::Scenario.build(:couple)
    sign_in(s.partner)
    receipt = E2E::CannedAI.expense(cents: 6_600, merchant: "Farmácia Popular", method: "debito",
                                    instrument: "itau", modality: "image")
    with_canned_ai(receipt: receipt) do
      share!(file: fixture_file_upload("receipt.jpg", "image/jpeg"))
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal s.partner, txn.created_by
    assert_equal s.account, txn.account
    assert_silent_channels(s)
  end

  private

  def sign_in_scenario(pack)
    s = E2E::Scenario.build(pack)
    sign_in(s.owner)
    s
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: E2E::Scenario::PASSWORD }
    assert_response :redirect
  end

  # The shells' upload (.plans/mobile/05 §2): cookie-authenticated multipart POST with
  # the custom capture header standing in for the CSRF token.
  def share!(file:, caption: nil)
    post captures_path, headers: CAPTURE_HEADERS,
                        params: { file: file, caption: caption }.compact
    assert_redirected_to transactions_path
  end

  # No reply channel: no chat bubbles (the thread must not even list the capture), no
  # sidecar sends.
  def assert_silent_channels(s)
    assert_empty ChatMessage.where(direction: "outbound"), "captures must never answer with bubbles"
    assert_empty ChatMessage.thread_for(s.owner).where(type: "CaptureMessage"), "captures stay out of the thread"
    assert_empty fake_sidecar.messages, "captures must never reach the sidecar"
  end
end
