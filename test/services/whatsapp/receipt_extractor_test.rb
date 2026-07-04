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

  test "is_receipt=false yields no amount (soft ack / park)" do
    ex = Whatsapp::ReceiptExtractor.build("is_receipt" => false)
    assert_not ex.amount_present?
    assert_equal 0.0, ex.overall_confidence
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
