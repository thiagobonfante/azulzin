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

  test "R$5000 em 10x on a d10/f10 card bought day 3 → 1 unpaid commitment, no eager posted parcels" do
    commitment = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: 500_000, count: 10,
                                           occurred_on: Date.new(2026, 7, 3), merchant: "celular")
    assert commitment.installment?
    assert_equal 10, commitment.installments_count
    assert_equal 500_000, commitment.total_cents
    assert_equal 50_000, commitment.amount_cents
    assert_equal Date.new(2026, 8, 1), commitment.starts_on # first parcel rides next month's bill
    assert_equal 0, commitment.payments.count, "parcels are computed occurrences, not eager rows"
    assert_equal 0, commitment.paid_count, "starts unpaid — advances as each fatura is marked paid"
  end

  test "total_cents holds the plan total exactly for adversarial inputs" do
    [ [ 100_001, 3 ], [ 10_035, 3 ], [ 1, 2 ] ].each do |total, count|
      c = Installments::Create.call(account: @user.account, created_by: @user, card: @card, total_cents: total, count: count,
                                    occurred_on: Date.new(2026, 7, 3), merchant: "x-#{total}")
      assert_equal total, c.total_cents
      assert_equal Installments::Create.split_cents(total, count).first, c.amount_cents
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
