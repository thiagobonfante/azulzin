require "test_helper"

class CreditCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @itau = Institution.find_by(code: "341")
  end

  test "index requires a completed onboarding" do
    @user.update!(onboarded_at: nil)
    get credit_cards_url
    assert_redirected_to onboarding_url
  end

  test "create adds a card with limit and current bill" do
    assert_difference -> { @user.account.credit_cards.count }, 1 do
      post credit_cards_url, as: :turbo_stream,
           params: { credit_card: { institution_id: @itau.id, credit_limit_reais: "8.000", current_bill_reais: "2.340,50" } }
    end
    card = @user.account.credit_cards.last
    assert_equal 800000, card.credit_limit_cents
    assert_equal 234050, card.current_bill_cents
  end

  test "create accepts last4 (digits-only) and card_type" do
    post credit_cards_url, as: :turbo_stream,
         params: { credit_card: { institution_id: @itau.id, last4: "1234", card_type: "virtual" } }
    card = @user.account.credit_cards.last
    assert_equal "1234", card.last4
    assert card.virtual?
  end

  test "create defaults card_type to physical" do
    post credit_cards_url, as: :turbo_stream, params: { credit_card: { institution_id: @itau.id } }
    assert @user.account.credit_cards.last.physical?
  end

  test "update changes last4 and card_type" do
    card = @user.account.credit_cards.create!(institution: @itau)
    patch credit_card_url(card), params: { credit_card: { last4: "9876", card_type: "virtual" } }
    card.reload
    assert_equal "9876", card.last4
    assert card.virtual?
  end

  test "destroy soft-deletes the card (leaves the kept list, row survives)" do
    card = @user.account.credit_cards.create!(institution: @itau)
    assert_difference -> { @user.account.credit_cards.kept.count }, -1 do
      delete credit_card_url(card), as: :turbo_stream
    end
    assert card.reload.soft_deleted?
  end

  # ── Phase 1: billing config (R2) ─────────────────────────────────────────

  test "edit renders the billing config form" do
    card = @user.account.credit_cards.create!(institution: @itau)
    get edit_credit_card_url(card)
    assert_response :success
    assert_select "form#credit_card_form"
  end

  test "configuring billing re-buckets the card's existing history into real faturas" do
    card = @user.account.credit_cards.create!(institution: @itau)
    old  = @user.account.transactions.create!(amount_cents: 1_000, occurred_on: Date.new(2026, 3, 4),
                                      status: "posted", direction: "expense", credit_card: card)
    assert_equal Date.new(2026, 3, 1), old.billing_month # calendar fallback while unconfigured
    patch credit_card_url(card), params: { credit_card: { bill_due_day: 10, closing_offset_days: 7 } }
    assert_equal Date.new(2026, 4, 1), old.reload.billing_month # March 4, d10/f7 → April fatura
  end

  test "return_to only honours the transactions token (open-redirect check)" do
    card = @user.account.credit_cards.create!(institution: @itau)
    patch credit_card_url(card), params: { return_to: "https://evil.example", month: "2026-07",
                                           credit_card: { bill_due_day: 10 } }
    assert_redirected_to credit_cards_path # forged URL rejected
    patch credit_card_url(card), params: { return_to: "transactions", month: "2026-07",
                                           credit_card: { bill_due_day: 12 } }
    assert_redirected_to transactions_path(month: "2026-07")
  end
end
