require "test_helper"

class Whatsapp::ExtractorTest < ActiveSupport::TestCase
  # A fake OpenRouter client that returns a canned parsed body.
  def client_returning(parsed)
    fake_result = Struct.new(:parsed).new(parsed)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| fake_result }
    client
  end

  test "computes amount_cents in Ruby from amount_raw (LLM never multiplies)" do
    client = client_returning({
      "amount_raw" => "1.234,56", "currency" => "BRL", "merchant" => "Padaria",
      "occurred_on" => nil, "payment_method" => "credito", "instrument_phrase" => "cartão Nubank",
      "field_confidence" => { "amount" => 0.9 }, "overall_confidence" => 0.82
    })
    ex = Whatsapp::Extractor.from_text(users(:confirmed), "gastei 1.234,56 na padaria no Nubank", client: client)

    assert_equal 123_456, ex.amount_cents
    assert_equal "Padaria", ex.merchant
    assert_equal "cartão Nubank", ex.instrument_phrase
    assert_equal "credito", ex.payment_method
    assert ex.amount_present?
    assert ex.instrument_named?
  end

  test "a bare integer amount ('gastei 32') converts to whole reais" do
    client = client_returning({
      "amount_raw" => "32", "payment_method" => "credito", "instrument_phrase" => "cartão Nubank",
      "field_confidence" => { "amount" => 0.9 }, "overall_confidence" => 0.85
    })
    ex = Whatsapp::Extractor.from_text(users(:confirmed), "Gastei 32 no cartão Nubank", modality: "audio", client: client)

    assert_equal 3_200, ex.amount_cents
    assert ex.amount_present?
    assert_equal "whatsapp_audio", ex.source
  end

  test "closed-set category line rides the user message, capped and usage-ordered" do
    user = users(:confirmed)
    Categories::SeedDefaults.call(user.account, locale: "pt-BR")
    sent = nil
    fake_result = Struct.new(:parsed).new({ "amount_raw" => "10" })
    client = Object.new
    client.define_singleton_method(:chat) { |**kwargs| sent = kwargs; fake_result }

    Whatsapp::Extractor.from_text(user, "10 no mercado", client: client)

    user_msg = sent[:messages].last[:content]
    assert_includes user_msg, "Categorias do usuário:"
    assert_includes user_msg, "Mercado"
    assert_equal "10 no mercado", user_msg.split("\n\n").first
    assert_not_includes sent[:messages].first[:content], "Categorias do usuário:" # system prompt stays static
  end

  test "no categories → no closed-set line (message is just the text)" do
    sent = nil
    fake_result = Struct.new(:parsed).new({ "amount_raw" => "10" })
    client = Object.new
    client.define_singleton_method(:chat) { |**kwargs| sent = kwargs; fake_result }

    Whatsapp::Extractor.from_text(users(:confirmed), "10 no mercado", client: client)
    assert_equal "10 no mercado", sent[:messages].last[:content]
  end

  test "rejects a future occurred_on and keeps a nil amount nil" do
    client = client_returning({ "amount_raw" => nil, "occurred_on" => (Date.current + 5).iso8601 })
    ex = Whatsapp::Extractor.from_text(users(:confirmed), "sei la", client: client)

    assert_nil ex.amount_cents
    assert_nil ex.occurred_on
    assert_not ex.amount_present?
    assert_equal "whatsapp_text", ex.source
  end
end
