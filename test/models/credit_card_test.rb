require "test_helper"

class CreditCardTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @inst = Institution.find_by(code: "341")
  end

  test "available credit is limit minus bill; usage ratio reflects it" do
    card = CreditCard.new(account: @user.account, institution: @inst, credit_limit_reais: "1000", current_bill_reais: "250")
    assert_equal 75000, card.available_cents
    assert_in_delta 0.25, card.usage_ratio, 0.001
  end

  test "an unknown bill counts as zero used" do
    card = CreditCard.new(account: @user.account, institution: @inst, credit_limit_reais: "1000")
    assert_equal 100000, card.available_cents
    assert_equal 0.0, card.usage_ratio
  end

  test "available and usage are nil when the limit is unknown" do
    card = CreditCard.new(account: @user.account, institution: @inst)
    assert_not card.limit_informed?
    assert_nil card.available_cents
    assert_nil card.usage_ratio
  end

  test "usage ratio clamps to 1 when the bill exceeds the limit" do
    card = CreditCard.new(account: @user.account, institution: @inst, credit_limit_reais: "100", current_bill_reais: "500")
    assert_equal 1.0, card.usage_ratio
  end

  test "negative amounts are rejected" do
    card = CreditCard.new(account: @user.account, institution: @inst, credit_limit_reais: "-5")
    assert_not card.valid?
  end

  test "a zero limit counts as not informed (no nil usage_ratio for the view to crash on)" do
    card = CreditCard.new(account: @user.account, institution: @inst, credit_limit_reais: "0")
    assert_equal 0, card.credit_limit_cents
    assert_not card.limit_informed?
    assert_nil card.usage_ratio
    assert_nil card.available_cents
  end

  # ── Committed usage: parcels and assinaturas hold limit ─────────────────────

  def configured_card(limit: "1000")
    CreditCard.create!(account: @user.account, institution: @inst, credit_limit_reais: limit,
                       bill_due_day: 10, closing_offset_days: 7)
  end

  test "a bare installment commitment (import) reserves its remaining parcels against the limit" do
    card = configured_card
    open = card.current_open_bill_month
    # Mid-plan: 5×R$100 started two bills ago → the open parcel + 2 future ones remain.
    Commitment.create!(account: @user.account, credit_card: card, name: "Notebook 5x", kind: "installment",
                       amount_cents: 10_000, total_cents: 50_000, installments_count: 5,
                       schedule_kind: "fixed_day", starts_on: open << 2)
    assert_equal 3 * 10_000, card.used_cents
    assert_equal 100_000 - 30_000, card.available_cents
  end

  test "a subscription reserves the open bill's charge until the real charge posts" do
    card = configured_card
    sub = Commitment.create!(account: @user.account, credit_card: card, name: "Netflix", kind: "subscription",
                             amount_cents: 5_500, schedule_kind: "fixed_day", starts_on: Date.current << 3)
    assert_equal 5_500, card.used_cents
    assert_equal 5_500, card.open_bill_cents
    # The charge posts and is linked → the posted row takes over, never double-counted.
    @user.account.transactions.create!(credit_card: card, commitment: sub, direction: "expense", status: "posted",
                               amount_cents: 5_500, occurred_on: Date.current)
    assert_equal 5_500, card.used_cents
    assert_equal 5_500, card.open_bill_cents
  end

  test "a card installment holds exactly the plan total (reserved unpaid parcels, no double count)" do
    card = configured_card(limit: "5000")
    Installments::Create.call(account: @user.account, created_by: @user, card: card, total_cents: 100_000, count: 10,
                              occurred_on: Date.current, merchant: "Sofá")
    assert_equal 100_000, card.used_cents
    assert_equal 500_000 - 100_000, card.available_cents
  end

  test "open_bill_cents falls back to the manual snapshot on an unconfigured card" do
    card = CreditCard.new(account: @user.account, institution: @inst, current_bill_reais: "250")
    assert_equal 25_000, card.open_bill_cents
  end
end
