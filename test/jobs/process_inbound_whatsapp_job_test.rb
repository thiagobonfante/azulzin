require "test_helper"

class ProcessInboundWhatsappJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @msg = WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
             wa_message_id: "wa-1", chat_id: "5511999998888@c.us",
             body: "gastei 13,23 no mercado", status: "received")
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      amount_raw: "13,23", amount_cents: 1_323, currency: "BRL", merchant: "mercado",
      occurred_on: nil, payment_method: "desconhecido", instrument_phrase: nil,
      field_confidence: {}, overall_confidence: 0.7, modality: "text",
      source: "whatsapp_text", raw: {}
    }.merge(overrides))
  end

  def run_job(ex)
    n = 0
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { ex }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { n += 1; { id: "out-#{n}" } }) { yield }
    end
  end

  test "below-floor confidence parks a pending_review transaction (in-zone date) and replies" do
    run_job(extraction) { ProcessInboundWhatsappJob.perform_now(@msg.id) }   # overall_confidence 0.7 < floor 80

    txn = @user.account.transactions.sole
    assert_equal 1_323, txn.amount_cents
    assert txn.pending_review?
    assert_equal "whatsapp_text", txn.source
    assert_equal @msg, txn.whatsapp_message
    assert_equal Time.current.in_time_zone("America/Sao_Paulo").to_date, txn.occurred_on
    assert_not txn.assigned?                       # no instrument phrase → unassigned
    assert_equal "processed", @msg.reload.status
  end

  test "idempotent: re-running the job does not double-post (source_message_id)" do
    run_job(extraction) do
      ProcessInboundWhatsappJob.perform_now(@msg.id)
      @msg.update_column(:status, "received")      # bypass the re-run guard to exercise txn-level idempotency
      ProcessInboundWhatsappJob.perform_now(@msg.id)
    end
    assert_equal 1, @user.account.transactions.count
  end

  test "no amount → opens an amount clarification (nothing posted)" do
    run_job(extraction(amount_raw: nil, amount_cents: nil)) do
      ProcessInboundWhatsappJob.perform_now(@msg.id)
    end
    txn = @user.account.transactions.sole
    assert txn.needs_clarification?
    assert_equal "amount", txn.ask["slot"]
    assert_equal 0, @user.account.transactions.spend.count   # nothing posted
    assert_equal "processed", @msg.reload.status
  end

  test "over the per-minute cap → skips AI (no extractor call), marks failed, posts nothing" do
    (ProcessInboundWhatsappJob::MAX_INBOUND_PER_MINUTE + 1).times do |i|
      WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
        wa_message_id: "flood-#{i}", chat_id: "5511999998888@c.us", body: "x", status: "processed")
    end
    # No AI stub: if the pipeline weren't short-circuited it would hit OpenRouter and raise.
    ProcessInboundWhatsappJob.perform_now(@msg.id)

    assert_equal "failed", @msg.reload.status
    assert_equal "rate_limited", @msg.error
    assert_equal 0, @user.account.transactions.count
  end
end
