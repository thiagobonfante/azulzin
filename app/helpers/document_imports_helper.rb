module DocumentImportsHelper
  # proposal kind → the pluralized i18n group used in the status-card summary.
  FOUND_GROUPS = { "bank_account" => :accounts, "credit_card" => :cards,
                   "income" => :incomes, "commitment" => :commitments }.freeze

  # "1 conta, 1 cartão e 14 compromissos encontrados" — built from the proposals jsonb, each
  # segment its own pluralized key, joined with the locale-aware to_sentence. nil when empty.
  def import_found_summary(import)
    counts = Hash.new(0)
    import.proposals.each do |proposal|
      group = FOUND_GROUPS[proposal["kind"]]
      counts[group] += 1 if group
    end
    return if counts.empty?

    parts = %i[accounts cards incomes commitments].filter_map do |group|
      t("document_imports.found.#{group}", count: counts[group]) if counts[group].positive?
    end
    t("document_imports.found.summary", parts: parts.to_sentence)
  end
end
