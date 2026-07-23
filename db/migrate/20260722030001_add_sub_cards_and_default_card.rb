class AddSubCardsAndDefaultCard < ActiveRecord::Migration[8.0]
  def change
    # One nullable self-FK, one level deep (.plans/credit-cards 04 §1): a card with a
    # parent is a sub-card (virtual / adicional); the cycle and the limit belong to the root.
    add_reference :credit_cards, :parent_card, foreign_key: { to_table: :credit_cards }

    # The per-member default plastic (04 §5) — the `locale` precedent: a scalar per-user
    # preference; each spouse defaults to their own card.
    add_reference :users, :default_credit_card, foreign_key: { to_table: :credit_cards }
  end
end
