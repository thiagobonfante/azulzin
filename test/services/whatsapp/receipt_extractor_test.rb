require "test_helper"

class Whatsapp::ReceiptExtractorTest < ActiveSupport::TestCase
  test "maps the printed total to cents in Ruby" do
    ex = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "total_raw" => "1.234,56", "merchant_name" => "Padaria",
      "payment_method" => "debito", "purchase_date" => nil,
      "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 }
    )
    assert_equal 123_456, ex.amount_cents
    assert_equal "Padaria", ex.merchant
    assert_equal "debito", ex.payment_method
    assert_equal "image", ex.modality
    assert_nil ex.instrument_phrase
  end

  test "the category guess flows through the extraction (resolved later by the Decider ladder)" do
    ex = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "total_raw" => "84,90", "merchant_name" => "Zaffari",
      "payment_method" => "debito", "purchase_date" => nil, "category" => "mercado",
      "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 }
    )
    assert_equal "mercado", ex.category

    no_guess = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "total_raw" => "84,90", "merchant_name" => "Zaffari",
      "payment_method" => "debito", "purchase_date" => nil, "category" => nil,
      "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 }
    )
    assert_nil no_guess.category
  end

  test "a Pix transfer receipt extracts amount, recipient, and the origin account phrase" do
    ex = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "document_type" => "transferencia", "total_raw" => "80,00",
      "merchant_name" => "Gabrielly Goncalves da Silva", "payment_method" => "pix",
      "origin_phrase" => "Nu Pagamentos Franciane Cristina Teixeira",
      "purchase_date" => Date.current.iso8601,
      "overall_confidence" => 0.92, "field_confidence" => { "total" => 0.95 }
    )
    assert_equal 8_000, ex.amount_cents
    assert_equal "pix", ex.payment_method
    assert_equal "Gabrielly Goncalves da Silva", ex.merchant
    assert_equal "Nu Pagamentos Franciane Cristina Teixeira", ex.instrument_phrase
    assert ex.instrument_named?
    assert_operator ex.overall_confidence, :>=, 0.80
  end

  test "the caption fills instrument_phrase and payment_method only when the receipt printed none" do
    ex = Whatsapp::ReceiptExtractor.build(
      { "is_receipt" => true, "total_raw" => "10,00", "payment_method" => "desconhecido",
        "origin_phrase" => nil, "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 } },
      "Cartão santander")
    assert_equal "Cartão santander", ex.instrument_phrase
    assert_equal "credito", ex.payment_method   # caption names crédito XOR débito

    printed = Whatsapp::ReceiptExtractor.build(
      { "is_receipt" => true, "document_type" => "transferencia", "total_raw" => "10,00",
        "payment_method" => "pix", "origin_phrase" => "Nu Pagamentos Franciane",
        "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 } },
      "Cartão santander")
    assert_equal "Nu Pagamentos Franciane", printed.instrument_phrase   # printed origin wins
    assert_equal "pix", printed.payment_method                          # printed method wins
  end

  test "an ambiguous caption (crédito AND débito words) never decides the payment method" do
    ex = Whatsapp::ReceiptExtractor.build(
      { "is_receipt" => true, "total_raw" => "10,00", "payment_method" => "desconhecido",
        "origin_phrase" => nil, "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 } },
      "cartão ou conta, não sei")
    assert_equal "desconhecido", ex.payment_method
  end

  test "from_message joins the caption into the vision prompt and hints the instrument" do
    user = users(:confirmed)
    msg = WhatsappMessage.create!(user: user, account: user.account, direction: "inbound",
                                  message_type: "image", wa_message_id: "wa-cap", chat_id: "x",
                                  body: "Cartão santander", status: "received")
    msg.media.attach(io: StringIO.new("fake-bytes"), filename: "r.jpg", content_type: "image/jpeg")

    parsed = { "is_receipt" => true, "total_raw" => "10,00", "payment_method" => "desconhecido",
               "origin_phrase" => nil, "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 } }
    captured = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, schema:|
      captured = messages
      Struct.new(:parsed).new(parsed)
    end

    ex = Whatsapp::ReceiptExtractor.from_message(msg, client: client)
    assert_includes captured.last[:content].first[:text], "Cartão santander"
    assert_equal "Cartão santander", ex.instrument_phrase
  end

  test "is_receipt=false yields no amount (soft ack / park)" do
    ex = Whatsapp::ReceiptExtractor.build("is_receipt" => false)
    assert_not ex.amount_present?
    assert_equal 0.0, ex.overall_confidence
    assert ex.not_receipt?
  end

  def pdf_msg
    user = users(:confirmed)
    msg = WhatsappMessage.create!(user: user, account: user.account, direction: "inbound",
                                  message_type: "document", wa_message_id: "wa-pdf-#{SecureRandom.hex(4)}",
                                  chat_id: "x", status: "received")
    msg.media.attach(io: StringIO.new("%PDF-fake"), filename: "comprovante.pdf",
                     content_type: "application/pdf")
    msg
  end

  test "a PDF document is rasterized to PNG (page 1) before the vision call" do
    parsed = { "is_receipt" => true, "total_raw" => "10,00", "payment_method" => "pix",
               "origin_phrase" => nil, "overall_confidence" => 0.9, "field_confidence" => { "total" => 0.9 } }
    captured = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, schema:|
      captured = messages
      Struct.new(:parsed).new(parsed)
    end

    ex = nil
    Imports::PdfRasterizer.stub(:call, ->(_bytes, max_pages:) { [ "png-bytes" ] }) do
      ex = Whatsapp::ReceiptExtractor.from_message(pdf_msg, client: client)
    end

    assert_equal 1_000, ex.amount_cents
    url = captured.last[:content].last[:image_url][:url]
    assert url.start_with?("data:image/png;base64,"), "PDF must reach vision as a PNG, never as raw application/pdf"
  end

  test "an unreadable PDF (corrupt / no Ghostscript) degrades to not_receipt instead of raising" do
    Imports::PdfRasterizer.stub(:call, ->(*) { raise Imports::ParseError, "pdf rasterization failed" }) do
      ex = Whatsapp::ReceiptExtractor.from_message(pdf_msg, client: Object.new)
      assert ex.not_receipt?
    end
  end

  test "a future purchase date caps confidence below the auto-post floor" do
    ex = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "total_raw" => "10,00",
      "purchase_date" => (Date.current + 10).iso8601,
      "overall_confidence" => 0.95, "field_confidence" => { "total" => 0.95 }
    )
    assert_operator ex.overall_confidence, :<=, 0.60
  end

  test "an unreadable total caps confidence" do
    ex = Whatsapp::ReceiptExtractor.build(
      "is_receipt" => true, "total_raw" => nil, "payment_method" => "credito",
      "overall_confidence" => 0.95, "field_confidence" => {}
    )
    assert_not ex.amount_present?
    assert_operator ex.overall_confidence, :<=, 0.50
  end
end
