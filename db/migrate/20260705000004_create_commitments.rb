class CreateCommitments < ActiveRecord::Migration[8.1]
  def change
    create_table :commitments do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :bank_account, foreign_key: true          # exactly one instrument (DB-enforced below)
      t.references :credit_card,  foreign_key: true
      t.references :category,     foreign_key: true          # payments/parcels inherit it

      t.string  :name, null: false, limit: 80                # "financiamento do carro", "Netflix"
      t.string  :kind, null: false                           # installment | fixed | subscription
      t.bigint  :amount_cents, null: false                   # per occurrence / per parcel
      t.bigint  :total_cents                                 # installment only, display ("5000 em 10x")
      t.string  :schedule_kind, null: false, default: "fixed_day"
      t.integer :schedule_day                                # nil allowed for subscription (charge day unknown)
      t.date    :starts_on, null: false                      # first-occurrence month anchor
      t.date    :ends_on                                     # fixed w/ end; nil = open-ended; derived for installment
      t.integer :installments_count                          # installment kind only
      t.string  :source                                      # "app" | "whatsapp"
      t.string  :source_message_id                           # WA idempotency for plan-creating messages
      t.datetime :archived_at
      t.timestamps

      t.check_constraint "num_nonnulls(bank_account_id, credit_card_id) = 1",
                         name: "commitments_exactly_one_instrument"
      t.check_constraint "(kind = 'installment') = (installments_count IS NOT NULL)",
                         name: "commitments_installment_count_paired"
      t.index [ :user_id, :kind ]
      t.index :source_message_id, unique: true, where: "source_message_id IS NOT NULL"
    end
  end
end
