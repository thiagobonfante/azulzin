class LinkWhatsappMessagesToTransactions < ActiveRecord::Migration[8.1]
  def change
    # Convenience back-link (the authoritative link is transactions.whatsapp_message_id).
    # Added after both tables exist to avoid a create-order cycle.
    add_reference :whatsapp_messages, :transaction, foreign_key: true, null: true
  end
end
