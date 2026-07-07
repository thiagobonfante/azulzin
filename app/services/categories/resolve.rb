module Categories
  # Resolve a free-text category label (typically an LLM guess) to one of the account's
  # kept categories — in Ruby, never an LLM id. Extracted from the duplicated
  # resolve_category in Whatsapp::Decider / Whatsapp::InstallmentDecider.
  class Resolve
    # Minimum trigram similarity to accept a fuzzy match (was a bare 0.75 literal
    # in two deciders). Distinct from Transaction::MATCH_ASSIGN_MIN (instruments).
    MATCH_MIN = 0.75

    # → Category or nil. Never creates.
    def self.call(account:, label:)
      term = TextMatch.normalize(label)
      return nil if term.blank?

      candidates = account.categories.kept.to_a
      # Exact normalized-name match wins immediately — the common case once
      # closed-set prompts make the model answer with the user's own names.
      exact = candidates.find { |c| TextMatch.normalize(c.name) == term }
      return exact if exact

      best = candidates.max_by { |c| TextMatch.similarity(term, TextMatch.normalize(c.name)) }
      best if best && TextMatch.similarity(term, TextMatch.normalize(best.name)) >= MATCH_MIN
    end
  end
end
