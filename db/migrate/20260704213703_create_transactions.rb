class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :bank_account, foreign_key: true          # nullable (pending/unassigned)
      t.references :credit_card,  foreign_key: true          # nullable

      t.bigint  :amount_cents,  null: false                  # money as integer cents (MoneyColumns)
      t.string  :direction,     null: false, default: "expense"   # expense | income | transfer
      t.string  :payment_method                              # authoritative rail (debito|credito|pix|...)
      t.string  :merchant
      t.string  :description
      t.date    :occurred_on,   null: false                  # computed in America/Sao_Paulo

      t.string  :status,        null: false, default: "pending_review"
      # posted | needs_confirmation | needs_clarification | needs_disambiguation
      # | pending_review | rejected | superseded
      t.integer :confidence                                  # 0..100 integer
      t.string  :source                                      # whatsapp_audio|whatsapp_receipt|whatsapp_text|manual

      t.jsonb   :extraction, null: false, default: {}        # raw LLM output + per-field conf + transcript ref
      t.jsonb   :match_meta, null: false, default: {}        # candidates, scores, margin, reason code
      t.jsonb   :ask,        null: false, default: {}        # question asked + numbered options (reply correlation)
      t.datetime :ask_expires_at

      t.references :whatsapp_message, foreign_key: true      # the inbound msg that produced it
      t.string :source_message_id                           # wa _serialized id — POSTING IDEMPOTENCY
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :transactions, :source_message_id, unique: true, where: "source_message_id IS NOT NULL"
    add_index :transactions, [ :user_id, :status ]

    # At most one instrument. A `posted` row may have zero (the "unassigned" case, assigned
    # in-app under silent auto-commit) or one — but never both. See .plans/whats (Review P0-3).
    add_check_constraint :transactions,
      "num_nonnulls(bank_account_id, credit_card_id) <= 1", name: "transactions_one_instrument_max"
  end
end
