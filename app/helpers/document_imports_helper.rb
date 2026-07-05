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

  # proposal kind → the pluralized review group key.
  REVIEW_GROUPS = { "bank_account" => "bank_accounts", "credit_card" => "credit_cards",
                    "income" => "incomes", "commitment" => "commitments" }.freeze

  def review_group_key(kind) = REVIEW_GROUPS.fetch(kind, kind)

  # Editable name input default: the suggested nickname/name, else the institution name.
  def proposal_name(proposal)
    proposal.dig("payload", "nickname").presence ||
      proposal.dig("payload", "name").presence ||
      Institution.find_by(code: proposal.dig("payload", "institution_code"))&.display_name
  end

  # The read-only line beside the name (balance, per-month amount, …). bank_account for Phase 1.
  def proposal_summary(proposal)
    case proposal["kind"]
    when "bank_account"
      cents = proposal.dig("payload", "balance_cents")
      t("document_imports.review.balance", amount: brl(cents)) if cents
    end
  end

  # "visto em: extrato Nubank · ter, 30 jun · 1 / 9100349-6" — from the first evidence entry.
  def proposal_evidence(proposal)
    evidence = Array(proposal["evidence"]).first
    return if evidence.blank?

    source = [ t("document_imports.kinds.#{evidence["kind"]}", default: nil), evidence["institution"] ]
             .compact_blank.join(" ")
    t("document_imports.review.seen_in",
      source: source.presence || "—",
      date:   evidence_date(evidence["date"]),
      amount: evidence["description"].presence || evidence_amount(evidence["amount_cents"]))
  end

  private

  def evidence_date(iso)
    iso.present? ? l(Date.iso8601(iso), format: :weekday_day) : "—"
  rescue ArgumentError, Date::Error
    "—"
  end

  def evidence_amount(cents) = cents ? brl(cents) : "—"
end
