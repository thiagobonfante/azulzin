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
    assert_difference -> { @user.credit_cards.count }, 1 do
      post credit_cards_url, as: :turbo_stream,
           params: { credit_card: { institution_id: @itau.id, credit_limit_reais: "8.000", current_bill_reais: "2.340,50" } }
    end
    card = @user.credit_cards.last
    assert_equal 800000, card.credit_limit_cents
    assert_equal 234050, card.current_bill_cents
  end

  test "destroy removes the card" do
    card = @user.credit_cards.create!(institution: @itau)
    assert_difference -> { @user.credit_cards.count }, -1 do
      delete credit_card_url(card), as: :turbo_stream
    end
  end
end
