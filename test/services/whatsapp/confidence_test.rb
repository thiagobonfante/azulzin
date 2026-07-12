require "test_helper"

class Whatsapp::ConfidenceTest < ActiveSupport::TestCase
  def extraction(**overrides)
    Whatsapp::Extraction.new({
      amount_raw: "13,23", amount_cents: 1_323,
      field_confidence: { "amount" => 0.9 }, overall_confidence: 0.85, modality: "text"
    }.merge(overrides))
  end

  test "capture score is the overconfidence-capped min, scaled by modality" do
    assert_equal 85, Whatsapp::Confidence.new(extraction).capture_score
    assert Whatsapp::Confidence.new(extraction).above_floor?
  end

  test "audio modality lowers the score below the floor" do
    c = Whatsapp::Confidence.new(extraction(modality: "audio"))   # 0.85 * 0.90 = 76.5 → 77
    assert_equal 77, c.capture_score
    assert_not c.above_floor?
  end

  test "missing amount scores zero" do
    assert_equal 0, Whatsapp::Confidence.new(extraction(amount_cents: nil)).capture_score
  end

  # "magalu 10x de 349,90": the value rides installment_parcel_raw with amount_raw null —
  # a verbatim parcel string is trusted like a verbatim amount.
  test "parcel-first installment with a verbatim parcel clears the floor" do
    c = Whatsapp::Confidence.new(extraction(
      amount_raw: nil, amount_cents: nil, intent: "installment_purchase",
      installments_count: 10, installment_parcel_raw: "349,90",
      field_confidence: { "amount" => 0 }, overall_confidence: 1.0,
      raw: { "transcript" => "magalu 10x de 349,90 no nubank" }))
    assert_equal 100, c.capture_score
    assert c.above_floor?
  end

  test "non-verbatim installment value falls back to overall confidence" do
    c = Whatsapp::Confidence.new(extraction(
      amount_raw: nil, amount_cents: nil, intent: "installment_purchase",
      installments_count: 10, installment_total_raw: "3499",
      field_confidence: { "amount" => 0 }, overall_confidence: 0.5,
      raw: { "transcript" => "parcelei o notebook em dez vezes" }))
    assert_equal 50, c.capture_score
    assert_not c.above_floor?
  end

  test "installment fields never score a non-installment intent" do
    c = Whatsapp::Confidence.new(extraction(
      amount_raw: nil, amount_cents: nil, intent: "expense",
      installment_parcel_raw: "349,90", raw: { "transcript" => "349,90" }))
    assert_equal 0, c.capture_score
  end

  test "floor is configurable" do
    original = Whatsapp::Confidence.floor
    Whatsapp::Confidence.floor = 90
    assert_not Whatsapp::Confidence.new(extraction).above_floor?   # 85 < 90
  ensure
    Whatsapp::Confidence.floor = original
  end
end
