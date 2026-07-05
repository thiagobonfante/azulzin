class AddColorAndIconToCategories < ActiveRecord::Migration[8.1]
  def change
    # Presentation only (R6): a palette hex + an icon key, both from a curated set. Nullable —
    # a category with neither renders with a neutral color and no glyph.
    add_column :categories, :color, :string
    add_column :categories, :icon,  :string
  end
end
