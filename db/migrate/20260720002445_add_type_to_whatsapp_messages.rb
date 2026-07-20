class AddTypeToWhatsappMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_messages, :type, :string
  end
end
