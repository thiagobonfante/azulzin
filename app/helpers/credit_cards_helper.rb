module CreditCardsHelper
  # The default star renders only when there is a choice to make — an account with one
  # plain card keeps its exact screenshot (04: "must not complicate the simple case").
  def show_default_star?
    @show_default_star = Current.account.credit_cards.kept.count > 1 if @show_default_star.nil?
    @show_default_star
  end

  # Picker labels (04 §3): sub-cards read "Root — apelido", indented under their root.
  def instrument_card_label(card)
    card.sub_card? ? "#{card.billing_root.display_name} — #{card.display_name}" : card.display_name
  end
end
