require "test_helper"

# The service-level WhatsApp opt-out (up-tier 01 §2): a deterministic, full-message-intent
# pre-pass — instant consent-off + ONE confirmation, before any extraction; never hijacks
# a message that merely contains a stop word mid-sentence.
class Notifications::StopCommandTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = users(:confirmed)
    @user.update!(phone: "5511912345678", phone_verified_at: Time.current,
                  whatsapp_id: "5511912345678", whatsapp_jid: "5511912345678@c.us")
  end

  def inbound(body)
    WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
                            wa_message_id: "wa-#{SecureRandom.hex(4)}", chat_id: "x",
                            body: body, status: "received")
  end

  def capture_sends(&block)
    bodies = []
    WhatsappService.stub(:send_message, ->(_to, body) { bodies << body; { id: "out-#{SecureRandom.hex(3)}" } }, &block)
    bodies
  end

  test "detect matches the stop phrases, accent- and case-insensitive, punctuation tolerated" do
    [ "parar", "PARAR", "Parar!", "parar.", "stop", "STOP",
      "para de avisar", "Pare de me avisar", "parar de avisar",
      "não quero mais avisos", "nao quero mais os avisos" ].each do |text|
      assert Notifications::StopCommand.detect(text), "#{text.inspect} should read as a stop"
    end
  end

  test "detect never hijacks a message that merely contains a stop word" do
    [ "gastei 50 no mercado sem parar", "quero parar de gastar tanto",
      "vou parar no mercado, 84,90 no débito", "paguei o estacionamento stop 20",
      "parar a assinatura da netflix", "" ].each do |text|
      assert_not Notifications::StopCommand.detect(text), "#{text.inspect} must NOT read as a stop"
    end
  end

  test "parar sets consent off and confirms exactly once, in the user's locale" do
    @user.notification_prefs.update!(whatsapp_consent: true)
    bodies = capture_sends { Notifications::StopCommand.call(inbound("parar")) }
    assert_not @user.notification_prefs.reload.whatsapp_consent?
    assert_includes bodies.sole, "parei os avisos"
  end

  test "parar works for a user with no preference row — creates it, consent stays off, still confirms" do
    assert_nil @user.notification_preference
    bodies = nil
    assert_difference -> { NotificationPreference.count }, 1 do
      bodies = capture_sends { Notifications::StopCommand.call(inbound("parar")) }
    end
    assert_not @user.reload.notification_preference.whatsapp_consent?
    assert_equal 1, bodies.size
  end

  test "interpreter pre-pass: parar stops the pipeline with ZERO extraction calls" do
    @user.notification_prefs.update!(whatsapp_consent: true)
    extracted = false
    msg = inbound("Parar")
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { extracted = true }) do
      capture_sends { Whatsapp::Interpreter.new(msg, msg.body).call }
    end
    assert_not extracted, "the stop pre-pass runs before any extraction"
    assert_not @user.notification_prefs.reload.whatsapp_consent?
  end

  test "parar mid-sentence flows to normal extraction and leaves consent alone" do
    @user.notification_prefs.update!(whatsapp_consent: true)
    extraction = Whatsapp::Extraction.new(
      intent: "expense", intent_confidence: 0.95, amount_raw: "84,90", amount_cents: 8_490,
      currency: "BRL", merchant: "mercado", occurred_on: nil, payment_method: "desconhecido",
      instrument_phrase: nil, field_confidence: { "amount" => 0.95 }, overall_confidence: 0.9,
      modality: "text", source: "whatsapp_text", raw: {})
    extracted = false
    msg = inbound("vou parar no mercado, 84,90 no débito")
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { extracted = true; extraction }) do
      capture_sends { Whatsapp::Interpreter.new(msg, msg.body).call }
    end
    assert extracted, "an expense mentioning a stop word still extracts"
    assert @user.notification_prefs.reload.whatsapp_consent?, "consent untouched"
  end

  test "after parar, a subsequent Deliver for that user sends nothing" do
    travel_to Time.utc(2026, 7, 7, 15, 0)   # 12:00 SP — outside quiet hours
    @user.notification_prefs.update!(whatsapp_consent: true, wa_intro_sent_at: 1.week.ago)
    WhatsappConnection.instance.update!(status: "connected")
    capture_sends { Notifications::StopCommand.call(inbound("parar")) }

    n = Notification.record!(user: @user, account: @user.account, kind: "bill_due",
                             period_key: Date.new(2026, 7, 8),
                             payload: { "name" => "Luz", "amount_cents" => 18_240,
                                        "due_on" => "2026-07-08", "days_until" => 1 })
    assert_no_difference -> { WhatsappMessage.count } do
      assert_not Notifications::Deliver.call(n), "consent gate is closed after the stop"
    end
    assert_nil n.reload.whatsapp_sent_at
  end
end
