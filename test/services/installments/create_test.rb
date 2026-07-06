require "test_helper"

class Installments::CreateTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "260")
    @card = CreditCard.create!(account: @user.account, institution: @inst, bill_due_day: 10, closing_offset_days: 10)
  end

  test "split_cents spreads the remainder across the first parcels and sums exactly" do
    assert_equal [ 33334, 33334, 33333 ], Installments::Create.split_cents(100_001, 3)
    assert_equal 10_035, Installments::Create.split_cents(10_035, 3).sum
    assert_equal [ 1, 0 ], Installments::Create.split_cents(1, 2)
  end

  test "R$5000 em 10x on a d10/f10 card bought day 3 → 1 commitment + 10 posted parcels of 50000" do
    commitment = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: 500_000, count: 10,
                                           occurred_on: Date.new(2026, 7, 3), merchant: "celular")
    parcels = commitment.payments.posted.order(:installment_number).to_a
    assert_equal 10, parcels.size
    assert(parcels.all? { |p| p.amount_cents == 50_000 })
    assert_equal 500_000, parcels.sum(&:amount_cents)
    assert_equal Date.new(2026, 8, 1), parcels.first.billing_month # founder R11: first parcel next month
    parcels.each_with_index { |p, i| assert_equal(Date.new(2026, 8, 1) >> i, p.billing_month, "parcel #{i + 1}") }
  end

  test "parcels sum to the total for adversarial inputs" do
    [ [ 100_001, 3 ], [ 10_035, 3 ], [ 1, 2 ] ].each do |total, count|
      c = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: total, count: count,
                                    occurred_on: Date.new(2026, 7, 3), merchant: "x-#{total}")
      assert_equal total, c.payments.posted.sum(:amount_cents)
    end
  end

  test "idempotent on source_message_id — a replay creates zero new rows" do
    a = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: 500_000, count: 10,
                                  occurred_on: Date.new(2026, 7, 3), merchant: "x", source_message_id: "wa-1")
    assert_no_difference [ "Commitment.count", "Transaction.count" ] do
      b = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: 500_000, count: 10,
                                    occurred_on: Date.new(2026, 7, 3), merchant: "x", source_message_id: "wa-1")
      assert_equal a, b
    end
  end
end
