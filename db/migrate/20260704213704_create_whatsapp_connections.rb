class CreateWhatsappConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :whatsapp_connections do |t|
      t.string   :status, null: false, default: "disconnected"
      # disconnected|initializing|qr_pending|authenticated|connected|logged_out|error
      t.string   :wa_id                                      # connected number, set on ready
      t.text     :qr_data_url                                # transient; streamed to admin; cleared on connect
      t.datetime :last_connected_at
      t.datetime :last_seen_at                               # heartbeat
      t.text     :last_error

      t.timestamps
    end
  end
end
