class CreateCreditCards < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_cards do |t|
      t.references :user,        null: false, foreign_key: true
      t.references :institution, null: false, foreign_key: true
      t.string  :nickname                    # optional label, e.g. "Cartão físico"
      t.bigint  :credit_limit_cents          # optional (limite total)
      t.bigint  :current_bill_cents          # optional; amount owed on the next bill (fatura)

      t.timestamps
    end
  end
end
