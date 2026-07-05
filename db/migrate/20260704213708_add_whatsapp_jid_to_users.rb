class AddWhatsappJidToUsers < ActiveRecord::Migration[8.1]
  def change
    # The full WhatsApp JID we reply to (e.g. "87797771833549@lid" or "5511...@c.us").
    # whatsapp_id stays digits-only for inbound matching; this keeps the exact address for
    # OUTBOUND, so @lid (linked-identity) contacts stay reachable.
    add_column :users, :whatsapp_jid, :string
  end
end
