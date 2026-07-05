class AddCardTypeToCreditCards < ActiveRecord::Migration[8.1]
  def change
    # Physical vs virtual card — identification/display only; no billing effect.
    add_column :credit_cards, :card_type, :string, default: "physical", null: false
  end
end
