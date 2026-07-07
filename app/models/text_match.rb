# Shared pure-string primitives for fuzzy matching, extracted from Whatsapp so
# non-WhatsApp services (Categories::*) don't depend on the channel namespace.
module TextMatch
  # Normalize a term the pt-BR way: strip accents, downcase, collapse whitespace.
  def self.normalize(term)
    I18n.transliterate(term.to_s).downcase.gsub(/\s+/, " ").strip
  end

  # Fuzzy string similarity in [0,1] — trigram (Sørensen–Dice) over space-padded
  # strings. Hand-rolled to avoid a native gem for a 2–15 row candidate set.
  def self.similarity(a, b)
    return 0.0 if a.blank? || b.blank?
    return 1.0 if a == b
    ta, tb = trigrams(a), trigrams(b)
    return 0.0 if ta.empty? || tb.empty?
    2.0 * (ta & tb).size / (ta.size + tb.size)
  end

  def self.trigrams(str)
    s = "  #{str} "
    (0..s.length - 3).map { |i| s[i, 3] }.uniq
  end
end
