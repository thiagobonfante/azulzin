require "test_helper"

# End-to-end decision pipeline through the job: real Matcher/Confidence/Decider, with the
# AI (Extractor) and the sidecar (WhatsappService) stubbed. Exercises the DECIDED silent
# auto-commit posture (Open Decision #5).
class Whatsapp::PipelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @card = CreditCard.create!(user: @user, institution: Institution.find_by(code: "260")) # Nubank
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      amount_raw: "13,23", amount_cents: 1_323, currency: "BRL", merchant: "supermercado",
      occurred_on: nil, payment_method: "credito", instrument_phrase: "cartão Nubank",
      field_confidence: { "amount" => 0.95 }, overall_confidence: 0.9,
      modality: "text", source: "whatsapp_text", raw: {}
    }.merge(overrides))
  end

  def inbound(body, id: "wa-#{SecureRandom.hex(4)}")
    WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
      wa_message_id: id, chat_id: "5511999998888@c.us", body: body, status: "received")
  end

  def run_pipeline(msg, ex = nil)
    stub_ex = ex || extraction
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { stub_ex }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "out-#{SecureRandom.hex(3)}" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end
  end

  test "high confidence + matched instrument → posted, assigned silently" do
    run_pipeline(inbound("gastei 13,23 no supermercado no cartão Nubank"))
    txn = @user.transactions.sole
    assert txn.posted?
    assert_equal @card, txn.credit_card
    assert_equal 1_323, txn.amount_cents
    assert txn.confirmed_at.present?
  end

  test "high confidence + unmatched instrument → posted UNASSIGNED (assign in-app)" do
    run_pipeline(inbound("gastei 50 no posto"), extraction(amount_cents: 5_000, instrument_phrase: nil, merchant: "posto"))
    txn = @user.transactions.sole
    assert txn.posted?
    assert_not txn.assigned?
  end

  test "shaky amount (below floor) → parked, not posted" do
    run_pipeline(inbound("acho que gastei uns 30"),
        extraction(amount_cents: 3_000, field_confidence: { "amount" => 0.4 }, overall_confidence: 0.4))
    txn = @user.transactions.sole
    assert txn.pending_review?
  end

  test "missing amount → asks, then a follow-up amount posts it (open-ask routing)" do
    run_pipeline(inbound("comprei no Nubank"), extraction(amount_raw: nil, amount_cents: nil))
    ask = @user.transactions.sole
    assert ask.needs_clarification?
    assert_equal "amount", ask.ask["slot"]
    assert_equal @card, ask.credit_card               # instrument resolved at ask time

    run_pipeline(inbound("137,90"))                            # open-ask path → ReplyRouter (no extractor call)
    ask.reload
    assert ask.posted?
    assert_equal 13_790, ask.amount_cents
    assert_equal 1, @user.transactions.count          # no second transaction
  end

  test "in-app safety net: reverse and reassign" do
    run_pipeline(inbound("gastei 13,23 no cartão Nubank"))
    txn = @user.transactions.sole
    other = BankAccount.create!(user: @user, institution: Institution.find_by(code: "341"))
    txn.assign_instrument!(other)
    assert_equal other, txn.bank_account
    assert_nil txn.credit_card
    txn.reverse!
    assert txn.rejected?
    assert_equal 0, @user.transactions.spend.count
  end
end
