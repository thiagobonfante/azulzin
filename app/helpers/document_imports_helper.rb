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
    when "credit_card"
      bits = []
      last4 = proposal.dig("payload", "last4")
      day   = proposal.dig("payload", "bill_due_day")
      bits << t("credit_cards.ending", last4: last4) if last4.present?
      bits << t("document_imports.review.due_day", day: day) if day.present?
      bits.join(" · ").presence
    when "commitment"
      commitment_summary(proposal)
    end
  end

  def commitment_summary(proposal)
    amount = brl(proposal.dig("payload", "amount_cents"))
    case proposal.dig("payload", "commitment_kind")
    when "installment"
      [ installment_label(proposal), amount ].compact.join(" · ")
    when "subscription"
      [ t("document_imports.review.per_month", amount: amount), t("document_imports.review.on_card") ].join(" · ")
    else
      day = proposal.dig("payload", "schedule_day")
      [ amount, (t("document_imports.review.due_day", day: day) if day.present?) ].compact.join(" · ")
    end
  end

  def installment_label(proposal)
    total = proposal.dig("payload", "installments_count")
    return unless total

    current = Array(proposal["evidence"]).filter_map { it["installment"]&.first }.first || 1
    t("document_imports.review.installment_label", current: current, total: total)
  end

  # commitment proposals → ordered {subscriptions, installments, fixed_bills} => [proposal, ...].
  COMMITMENT_SUBGROUPS = { "subscription" => "subscriptions", "installment" => "installments",
                           "fixed" => "fixed_bills" }.freeze

  def commitment_subgroups(proposals)
    proposals.group_by { COMMITMENT_SUBGROUPS.fetch(it.dig("payload", "commitment_kind"), "fixed_bills") }
             .sort_by { |key, _| COMMITMENT_SUBGROUPS.values.index(key) || 99 }
             .to_h
  end

  # cents → the pt-BR decimal string the income amount input round-trips through Money.to_cents.
  def reais_value(cents)
    return if cents.nil?

    format("%.2f", cents / 100.0).tr(".", ",")
  end

  # "visto em: extrato Nubank · ter, 30 jun · 1 / 9100349-6" — from the first evidence entry,
  # with a "+N ocorrências" tail when a proposal merged multiple rows (e.g. Google One).
  def proposal_evidence(proposal)
    evidence = Array(proposal["evidence"])
    first = evidence.first
    return if first.blank?

    source = [ t("document_imports.kinds.#{first["kind"]}", default: nil), first["institution"] ]
             .compact_blank.join(" ")
    line = t("document_imports.review.seen_in",
             source: source.presence || "—",
             date:   evidence_date(first["date"]),
             amount: first["description"].presence || evidence_amount(first["amount_cents"]))
    return line if evidence.size < 2

    "#{line} #{t('document_imports.review.more_evidence', count: evidence.size - 1)}"
  end

  private

  def evidence_date(iso)
    iso.present? ? l(Date.iso8601(iso), format: :weekday_day) : "—"
  rescue ArgumentError, Date::Error
    "—"
  end

  def evidence_amount(cents) = cents ? brl(cents) : "—"
end
