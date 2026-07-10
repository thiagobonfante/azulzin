require "test_helper"

class Whatsapp::CaptureStatsTest < ActiveSupport::TestCase
  setup { @account = users(:confirmed).account }

  def txn(source:, confidence:, cents: 1_000, merchant: "mercado",
          extraction: nil, deleted: false)
    Transaction.create!(
      account: @account, amount_cents: cents, merchant: merchant,
      occurred_on: Date.current, billing_month: Date.current.beginning_of_month,
      status: "posted", source: source, confidence: confidence,
      extraction: extraction || { "amount_cents" => cents, "merchant" => merchant },
      deleted_at: (Time.current if deleted)
    )
  end

  test "buckets by capture posture and counts corrections against the frozen extraction" do
    txn(source: "whatsapp_audio", confidence: 90)                                     # auto, untouched
    txn(source: "whatsapp_audio", confidence: 85, cents: 1_200, merchant: "Posto X",  # auto, human fixed both
        extraction: { "amount_cents" => 1_000, "merchant" => "posto" })
    txn(source: "whatsapp_audio", confidence: 40)                                     # parked
    txn(source: "whatsapp_audio", confidence: 0)                                      # asked (no amount)
    txn(source: "whatsapp_audio", confidence: 90, deleted: true)                      # auto, undone
    txn(source: "whatsapp_text",  confidence: 90)                                     # other bucket

    stats = Whatsapp::CaptureStats.call(since: 1.day.ago)
    audio = stats["whatsapp_audio"]

    assert_equal 5, audio[:total]
    assert_equal 3, audio[:auto_posted]
    assert_equal 1, audio[:parked]
    assert_equal 1, audio[:asked]
    assert_equal 1, audio[:amount_corrected]
    assert_equal 1, audio[:merchant_corrected]
    assert_equal 1, audio[:undone]
    assert_equal 1, stats["whatsapp_text"][:total]
    assert_equal({ total: 0 }, stats["whatsapp_receipt"])
  end

  test "ignores rows outside the window and rows the floor never scored (nil confidence)" do
    old = txn(source: "whatsapp_text", confidence: 90)
    old.update_columns(created_at: 100.days.ago)
    txn(source: "whatsapp_text", confidence: nil)   # income/transfer-style row: not floor-gated

    assert_equal({ total: 0 }, Whatsapp::CaptureStats.call(since: 90.days.ago)["whatsapp_text"])
  end
end
