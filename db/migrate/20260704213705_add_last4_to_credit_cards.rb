class AddLast4ToCreditCards < ActiveRecord::Migration[8.1]
  def change
    # Digits-only last four; high-leverage for same-bank card disambiguation ("final 1234").
    add_column :credit_cards, :last4, :string
  end
end
