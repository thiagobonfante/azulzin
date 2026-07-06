require "test_helper"

class Imports::ConfidenceTest < ActiveSupport::TestCase
  test "a deterministic signal floors confidence at 0.9 when no cap fires" do
    row = { "amount_cents" => 1000, "date" => "2026-06-01", "signals" => [ "debito_automatico" ] }
    assert_equal 0.9, Imports::Confidence.effective(row, 0.5, label: "fixed_bill")
  end

  test "single-month income caps at 0.7 — never pre-checked" do
    row = { "amount_cents" => 4_802_580, "date" => "2026-06-03", "signals" => [] }
    conf = Imports::Confidence.effective(row, 0.95, label: "income", single_month: true)
    assert_equal 0.7, conf
    assert_operator conf, :<, Imports::Confidence::REVIEW_FLOOR
  end

  test "a missing amount caps at 0.5 even with a deterministic signal (floor never overrides a cap)" do
    row = { "amount_cents" => 0, "date" => "2026-06-01", "signals" => [ "debito_automatico" ] }
    assert_equal 0.5, Imports::Confidence.effective(row, 0.9, label: "fixed_bill")
  end

  test "an unparseable date caps at 0.6 over the signal floor" do
    row = { "amount_cents" => 1000, "date" => nil, "signals" => [ "installment_counter" ] }
    assert_equal 0.6, Imports::Confidence.effective(row, 0.9, label: "installment")
  end

  test "the vision cap lands reads in Para revisar" do
    row = { "amount_cents" => 1000, "date" => "2026-06-01", "signals" => [] }
    assert_equal 0.75, Imports::Confidence.effective(row, 0.95, label: "fixed_bill", vision: true)
  end
end
