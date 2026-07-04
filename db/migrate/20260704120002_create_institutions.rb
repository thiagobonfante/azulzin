class CreateInstitutions < ActiveRecord::Migration[8.1]
  def change
    create_table :institutions do |t|
      t.string  :code,             null: false           # COMPE bank code (e.g. "260"), leading zeros kept
      t.string  :name,             null: false
      t.string  :initials,         null: false           # monogram fallback when no logo, e.g. "NU", "BB"
      t.string  :brand_color,      null: false           # hex, drives the avatar / monogram
      t.string  :logo_path                               # nil ⇒ fall back to a brand-color monogram
      t.boolean :supports_account, null: false, default: true
      t.boolean :supports_card,    null: false, default: true
      t.integer :position,         null: false, default: 0

      t.timestamps
    end

    add_index :institutions, :code, unique: true
    add_index :institutions, :position
  end
end
