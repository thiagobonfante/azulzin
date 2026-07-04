class CreateWhatsappMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :whatsapp_messages do |t|
      t.references :user, foreign_key: true                  # nullable (unknown sender path)
      t.string   :direction,     null: false                 # inbound | outbound
      t.string   :wa_message_id                              # _serialized — UNIQUE, inbound idempotency
      t.string   :chat_id                                    # "5511...@c.us"
      t.string   :message_type                               # text | image | audio | document
      t.text     :body
      t.text     :transcription                              # audio → text (stored for echo + audit)
      t.jsonb    :ai_result, null: false, default: {}        # raw extraction snapshot
      t.string   :status, null: false, default: "received"   # received|processing|processed|failed|sent
      t.text     :error
      t.datetime :processed_at
      # transaction_id back-link FK added after :transactions exists (avoids a create-order cycle)

      t.timestamps
    end

    # THE inbound idempotency primitive — the sidecar redelivers on retry.
    add_index :whatsapp_messages, :wa_message_id, unique: true, where: "wa_message_id IS NOT NULL"
    add_index :whatsapp_messages, [ :user_id, :created_at ]
  end
end
