require "test_helper"

# Speed-up gate (round 3 decision 6): purchase + active + paid parcel + positive sobra with
# sobra × 5 ≥ parcel (the 20% threshold, integer math). Sobra comes from MonthSummary.
class Goals::SpeedUpOfferTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.utc(2026, 7, 15, 12)
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @savings_account = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    @month    = Date.new(2026, 7, 1)
    @goal = @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                                   target_date: Date.new(2027, 12, 1), status: "active",
                                   monthly_target_cents: 300_000, starts_on: @month,
                                   bank_account: @savings_account)
    @commitment = @account.commitments.create!(kind: "savings", name: "Carro", goal: @goal,
                                               bank_account: @checking, amount_cents: 300_000,
                                               starts_on: @month, schedule_day: 5, schedule_kind: "fixed_day")
  end

  teardown { travel_back }

  def income!(cents)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: cents,
                                  bank_account: @checking, occurred_on: @month,
                                  billing_month: @month, billing_month_manual: true)
  end

  test "paid parcel + spare sobra → offer with the sobra and the commitment's plumbing" do
    income!(900_000)
    Commitments::MarkPaid.call(@commitment, @month)
    offer = Goals::SpeedUpOffer.for(@goal)
    assert offer
    assert_equal 600_000, offer.surplus_cents                       # 900_000 − 300_000 guardado
    assert_equal @checking.id, offer.source_bank_account_id
    assert_equal @savings_account.id, offer.destination_bank_account_id
  end

  test "boundary: sobra × 5 == parcel passes; one cent below fails" do
    income!(360_000)                                              # sobra after pay = 60_000, ×5 = parcel
    Commitments::MarkPaid.call(@commitment, @month)
    assert Goals::SpeedUpOffer.for(@goal)

    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 1,
                                  bank_account: @checking, occurred_on: @month,
                                  billing_month: @month, billing_month_manual: true)
    assert_nil Goals::SpeedUpOffer.for(@goal)                     # sobra 59_999 → below 20%
  end

  test "no offer while this month's parcel is unpaid" do
    income!(900_000)
    assert_nil Goals::SpeedUpOffer.for(@goal)
  end

  test "no offer without a savings commitment, on a non-active goal, or on savings_rate" do
    income!(900_000)
    Commitments::MarkPaid.call(@commitment, @month)
    assert Goals::SpeedUpOffer.for(@goal)

    @goal.update!(status: "achieved", achieved_at: Time.current)
    assert_nil Goals::SpeedUpOffer.for(@goal)

    sr = @account.goals.create!(name: "Guardar", kind: "savings_rate", target_cents: 100_000,
                                status: "active", monthly_target_cents: 100_000,
                                starts_on: @month, bank_account: @savings_account)
    assert_nil Goals::SpeedUpOffer.for(sr)
  end

  test "no offer when the sobra is zero or negative" do
    income!(300_000)                                              # everything goes to the parcel
    Commitments::MarkPaid.call(@commitment, @month)
    assert_nil Goals::SpeedUpOffer.for(@goal)
  end
end
