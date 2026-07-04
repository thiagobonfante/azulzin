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

  test "floor is configurable" do
    original = Whatsapp::Confidence.floor
    Whatsapp::Confidence.floor = 90
    assert_not Whatsapp::Confidence.new(extraction).above_floor?   # 85 < 90
  ensure
    Whatsapp::Confidence.floor = original
  end
end
