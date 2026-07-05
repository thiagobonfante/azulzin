class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :user, null: false, foreign_key: true
      t.citext  :name, null: false               # case-insensitive uniqueness ("Mercado" == "mercado")
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :categories, [ :user_id, :name ], unique: true
  end
end
