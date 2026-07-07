# Namespace + the shared auto-categorization ladder (.plans/auto-categories 01 §5):
# the user's own history (merchant memory) first, the LLM's label guess second, nil last.
module Categories
  # Cap on category names injected into LLM prompts (closed-set line).
  CLOSED_SET_MAX = 30

  # → [category_id, category_source] — [nil, nil] when neither step fires.
  def self.auto_assign(account:, merchant:, label:)
    if (memory = Suggest.call(account: account, merchant: merchant))
      [ memory.category.id, "memory" ]
    elsif (cat = Resolve.call(account: account, label: label))
      [ cat.id, "ai" ]
    else
      [ nil, nil ]
    end
  end

  # One prompt line naming the account's categories (usage-ordered, capped) so the LLM
  # answers inside the user's own taxonomy. Still a STRING answer — never an id; resolution
  # stays in Ruby (Resolve). nil when the account has no categories. `field` names the
  # schema property the model should answer with ("category", "category_guess").
  def self.closed_set_line(account, field: "category")
    return nil unless account
    names = account.categories.kept
                   .left_joins(:categorized_transactions)
                   .group("categories.id")
                   .order(Arel.sql("COUNT(transactions.id) DESC"), :position)
                   .limit(CLOSED_SET_MAX)
                   .pluck(:name)
    return nil if names.empty?
    "Categorias do usuário: #{names.join(", ")}. Responda #{field} com exatamente um desses nomes, ou null se nenhum servir."
  end
end
