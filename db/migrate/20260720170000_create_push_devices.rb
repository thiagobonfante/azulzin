class CreatePushDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :push_devices do |t|
      t.references :user,    null: false, foreign_key: true
      # Sign-out / password-reset destroy Sessions → dependent: :destroy revokes push;
      # no signed-out device ever receives balances (.plans/mobile/04 §2).
      t.references :session, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :token,    null: false, index: { unique: true }
      t.string :app_version
      t.datetime :last_registered_at, null: false
      t.timestamps
    end

    # The push claim, mirroring whatsapp_sent_at (atomic update_all claim).
    add_column :notifications, :push_sent_at, :datetime
    # In-app kill switch; the OS-level permission is the real consent.
    add_column :notification_preferences, :push_enabled, :boolean, default: true, null: false
  end
end
