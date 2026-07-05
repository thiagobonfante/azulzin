module Categories
  # Seeds the default categories for a user at onboarding, copied from t("categories.defaults")
  # IN THE USER'S LOCALE. Idempotent: find_or_create_by! per name (citext ⇒ case-insensitive),
  # so re-running restores a deleted default without duplicating survivors (09 P1 #14). After
  # seeding they are plain user rows with zero runtime i18n coupling — rename/delete freely.
  class SeedDefaults
    def self.call(user)
      names = I18n.t("categories.defaults", locale: user.locale)
      names.each_with_index do |name, position|
        user.categories.find_or_create_by!(name: name) { |c| c.position = position }
      end
    end
  end
end
