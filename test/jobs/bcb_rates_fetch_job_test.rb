require "test_helper"

# The daily SGS upsert (.plans/credit-cards 02 §2). The HTTP edge is stubbed at
# fetch_latest — no test ever calls the BCB API.
class BcbRatesFetchJobTest < ActiveSupport::TestCase
  MAY = Date.new(2026, 5, 1)

  test "upserts one row per kind, idempotently for the same reference month" do
    fake = ->(series_id) { { rate: BigDecimal(series_id == 25_477 ? "15.09" : "9.26"), reference_month: MAY } }
    2.times { BcbRates::FetchJob.stub(:fetch_latest, fake) { BcbRates::FetchJob.perform_now } }

    assert_equal 2, BcbRate.count
    assert_equal BigDecimal("15.09"), BcbRate.current("rotativo").monthly_rate
    assert_equal BigDecimal("9.26"),  BcbRate.current("parcelamento").monthly_rate
  end

  test "a failed fetch keeps serving the last stored row" do
    BcbRate.create!(kind: "rotativo", monthly_rate: BigDecimal("15.09"),
                    reference_month: MAY, fetched_at: Time.current)

    BcbRates::FetchJob.stub(:fetch_latest, ->(_id) { raise Timeout::Error }) do
      BcbRates::FetchJob.perform_now   # must not raise
    end

    assert_equal BigDecimal("15.09"), BcbRate.current("rotativo").monthly_rate
  end
end
