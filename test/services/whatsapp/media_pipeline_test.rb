require "test_helper"

# Audio (Phase 3) + image (Phase 4) branches through the job. STT and vision are the
# external AI boundaries — stubbed; the Matcher/Confidence/Decider run for real.
class Whatsapp::MediaPipelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @card = CreditCard.create!(account: @user.account, institution: Institution.find_by(code: "260")) # Nubank
  end

  def inbound(type, content_type, filename)
    m = WhatsappMessage.create!(user: @user, direction: "inbound", message_type: type,
          wa_message_id: "wa-#{SecureRandom.hex(4)}", chat_id: "5511999998888@c.us", status: "received")
    m.media.attach(io: StringIO.new("fake-bytes"), filename: filename, content_type: content_type)
    m
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      amount_raw: "13,23", amount_cents: 1_323, currency: "BRL", merchant: "supermercado",
      occurred_on: nil, payment_method: "credito", instrument_phrase: "cartão Nubank",
      field_confidence: { "amount" => 0.95 }, overall_confidence: 0.95,
      modality: "audio", source: "whatsapp_audio", raw: {}
    }.merge(overrides))
  end

  test "audio: transcribes, stores the transcript, feeds it to extraction, and posts" do
    msg = inbound("audio", "audio/ogg", "note.ogg")
    seen_text = nil
    Whatsapp::SttClient.stub(:transcribe, ->(*_a, **_k) { "gastei 13,23 no cartão Nubank" }) do
      Whatsapp::Extractor.stub(:from_text, ->(_u, text, **_k) { seen_text = text; extraction }) do
        WhatsappService.stub(:send_message, ->(*_a) { { id: "o" } }) do
          ProcessInboundWhatsappJob.perform_now(msg.id)
        end
      end
    end

    assert_equal "gastei 13,23 no cartão Nubank", msg.reload.transcription
    assert_equal "gastei 13,23 no cartão Nubank", seen_text        # transcript flows into extraction
    txn = @user.account.transactions.sole
    assert txn.posted?
    assert_equal "whatsapp_audio", txn.source
    assert_equal @card, txn.credit_card
  end

  test "image: vision extracts a receipt; KIND (crédito) + single card → posted assigned" do
    msg = inbound("image", "image/jpeg", "receipt.jpg")
    receipt = extraction(payment_method: "credito", instrument_phrase: nil, amount_cents: 1_435,
                         amount_raw: "14,35", merchant: "Restaurante X", modality: "image",
                         source: "whatsapp_receipt")
    Whatsapp::ReceiptExtractor.stub(:from_message, ->(*_a, **_k) { receipt }) do
      WhatsappService.stub(:send_message, ->(*_a) { { id: "o" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end

    txn = @user.account.transactions.sole
    assert txn.posted?
    assert_equal @card, txn.credit_card          # kind_only match (crédito + one card)
    assert_equal 1_435, txn.amount_cents
    assert_equal "whatsapp_receipt", txn.source
  end
end
