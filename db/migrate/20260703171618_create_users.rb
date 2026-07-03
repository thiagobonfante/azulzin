class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :users do |t|
      t.citext   :email_address, null: false
      t.string   :password_digest        # nullable: OAuth-only users have no password
      t.datetime :confirmed_at           # null = email not yet verified
      t.string   :locale, null: false, default: "pt-BR"   # UI + email language (ADR 0006)
      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
