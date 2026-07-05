module Categories
  # Seeds the default categories for a user at onboarding, copied from t("categories.defaults")
  # IN THE USER'S LOCALE. Idempotent: find_or_create_by! per name (citext ⇒ case-insensitive),
  # so re-running restores a deleted default without duplicating survivors (09 P1 #14). After
  # seeding they are plain user rows with zero runtime i18n coupling — rename/delete freely.
  class SeedDefaults
    # Color + icon per default position (locale-independent: names translate, the look doesn't).
    # Applied on create only, so a user's later edits are never overwritten.
    META = [
      [ "#22C55E", "cart" ],       # Mercado
      [ "#F97316", "utensils" ],   # Restaurantes
      [ "#3B82F6", "truck" ],      # Transporte
      [ "#14B8A6", "home" ],       # Moradia
      [ "#F59E0B", "document" ],   # Contas
      [ "#EF4444", "heart" ],      # Saúde
      [ "#8B5CF6", "cap" ],        # Educação
      [ "#EC4899", "ticket" ],     # Lazer
      [ "#06B6D4", "arrow-path" ], # Assinaturas
      [ "#8B5CF6", "bag" ],        # Vestuário
      [ "#3B82F6", "plane" ],      # Viagem
      [ "#64748B", "tag" ],        # Outros
    ].freeze

    def self.call(user)
      names = I18n.t("categories.defaults", locale: user.locale)
      names.each_with_index do |name, position|
        user.categories.find_or_create_by!(name: name) do |c|
          c.position = position
          c.color, c.icon = META[position] if META[position]
        end
      end
    end
  end
end
