# One-off backfill: give the out-of-the-box categories of users who onboarded before colors/icons
# existed the same look new users get. Matches by default name (either locale); renamed or custom
# categories keep their neutral default until edited. Idempotent — only fills blank colors.
class BackfillCategoryColorsAndIcons < ActiveRecord::Migration[8.1]
  def up
    name_meta = {}
    %w[pt-BR en].each do |locale|
      Array(I18n.t("categories.defaults", locale: locale, default: [])).each_with_index do |name, i|
        meta = Categories::SeedDefaults::META[i]
        name_meta[name.to_s.downcase] = meta if meta
      end
    end

    Category.where(color: [ nil, "" ]).find_each do |category|
      meta = name_meta[category.name.to_s.downcase]
      category.update_columns(color: meta[0], icon: meta[1]) if meta
    end
  end

  def down
    # Presentation backfill — leave user data alone on rollback.
  end
end
