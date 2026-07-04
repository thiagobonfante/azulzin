class AddWhatsappAndAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin,             :boolean, null: false, default: false
    add_column :users, :whatsapp_id,       :string   # normalized digits, set at verification
    add_column :users, :phone_verified_at, :datetime

    # Unique so two accounts can never verify the same number; partial so unverified
    # users (whatsapp_id NULL) don't collide. Sender resolution is exact equality on
    # this column — never a fuzzy `.first`. See .plans/whats (Review P0-1).
    add_index :users, :whatsapp_id, unique: true, where: "whatsapp_id IS NOT NULL"
  end
end
