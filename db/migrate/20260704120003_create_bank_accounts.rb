class CreateBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_accounts do |t|
      t.references :user,        null: false, foreign_key: true
      t.references :institution, null: false, foreign_key: true
      t.string  :nickname                    # optional label, e.g. "Conta salário"
      t.string  :agency                       # optional (agência)
      t.string  :account_number               # optional (número da conta)
      t.bigint  :balance_cents                # optional; nil ⇒ balance not informed

      t.timestamps
    end
  end
end
