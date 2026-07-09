module TransactionsHelper
  # The account's accounts/cards, loaded once per render for the instrument picker.
  def inbox_bank_accounts
    @inbox_bank_accounts ||= Current.account.bank_accounts.kept.includes(:institution).order(:created_at)
  end

  def inbox_credit_cards
    @inbox_credit_cards ||= Current.account.credit_cards.kept.includes(:institution).order(:created_at)
  end

  # Grouped <optgroup> options (accounts, then cards) for the instrument <select>.
  def instrument_option_groups
    [ [ t("app.nav.accounts"), inbox_bank_accounts.map { |a| [ a.display_name, "bank_account-#{a.id}" ] } ],
      [ t("app.nav.cards"),    inbox_credit_cards.map  { |c| [ c.display_name, "credit_card-#{c.id}" ] } ] ]
  end

  # The token matching a transaction's current instrument (for the select's selected value).
  def current_instrument_token(txn)
    return "bank_account-#{txn.bank_account_id}" if txn.bank_account_id
    return "credit_card-#{txn.credit_card_id}"   if txn.credit_card_id

    nil
  end

  # daisyUI badge class for a transaction status, so the inbox reads at a glance.
  def transaction_status_badge(status)
    { "posted"               => "badge-success",
      "pending_review"       => "badge-ghost",
      "needs_confirmation"   => "badge-warning",
      "needs_clarification"  => "badge-warning",
      "needs_disambiguation" => "badge-warning" }.fetch(status, "badge-ghost")
  end

  # Where the month went: one stacked bar of spend by category (each in its color) with the
  # leftover (sobra) as a blue tail — reuses the category palette so the split reads at a glance.
  # Returns nil (nothing to show) when there's neither spend nor a positive leftover.
  def monthly_flow_chart(account, month)
    summary = MonthSummary.new(account, month)
    # Posted expenses by category with the still-unpaid debit commitments folded in — the ONE
    # spend map (Budgets::Actuals), shared with Budgets::Check so bars and alerts always agree.
    spend_by_cat = Budgets::Actuals.for(account, month, summary: summary)
    total_spend = spend_by_cat.values.sum
    left = [ summary.remaining_cents, 0 ].max
    base = total_spend + left
    return if base.zero?

    cats = account.categories.kept.where(id: spend_by_cat.keys.compact).index_by(&:id)
    segments = spend_by_cat.map { |cat_id, cents|
      cat = cats[cat_id]
      { label: cat&.name || t("transactions.ledger.uncategorized"),
        color: cat&.display_color || Category::DEFAULT_COLOR, cents: cents }
    }.sort_by { |s| -s[:cents] }

    top    = segments.first(5)
    others = segments.drop(5).sum { |s| s[:cents] }
    parts  = top.dup
    parts << { label: t("transactions.ledger.other_categories"), color: Category::DEFAULT_COLOR, cents: others } if others.positive?
    parts << { label: t("transactions.hero.remaining"), color: "var(--color-primary)", cents: left } if left.positive?

    bar = content_tag(:div, class: "flex h-2.5 overflow-hidden rounded-full bg-base-200",
                      role: "img", "aria-label": t("transactions.hero.allocation_label")) do
      safe_join(parts.map { |s| flow_segment(s, base) })
    end
    legend = content_tag(:div, safe_join(parts.map { |s| flow_legend_item(s) }),
                         class: "mt-2.5 flex flex-wrap gap-x-3 gap-y-1")
    safe_join([ bar, legend ])
  end

  # R2 manual-move options for a card row: current billing_month −1..+3, month names, with the
  # engine's automatic choice suffixed so overrides are visually distinct (02 §5).
  def fatura_month_options(txn)
    auto = txn.credit_card.billing_month_for(txn.occurred_on)
    auto = auto >> (txn.installment_number - 1) if txn.installment_number
    (-1..3).map do |offset|
      m = txn.billing_month >> offset
      label = l(m, format: :month_year)
      label += " · #{t('transactions.row.bill_auto')}" if m == auto
      [ label, m.strftime("%Y-%m-%d") ]
    end
  end

  # Today's calendar month in the app timezone — the reference for month mode in views.
  def hub_today = Date.current.in_time_zone("America/Sao_Paulo").to_date

  # The one UI trace of a soft delete (doc 05 §2.8): a referenced-but-deleted parent
  # (category / instrument) renders its name with " (excluído)" appended. nil for kept records.
  def deleted_suffix(record)
    " #{t('shared.deleted_suffix')}" if record.respond_to?(:soft_deleted?) && record.soft_deleted?
  end

  private
    # One coloured slice of the allocation bar (colours are validated hexes / a theme var).
    def flow_segment(seg, base)
      return "".html_safe if seg[:cents] <= 0
      content_tag(:span, "", class: "block h-full",
                  style: "width: #{seg[:cents].fdiv(base) * 100}%; background-color: #{seg[:color]}",
                  title: "#{seg[:label]} · #{brl(seg[:cents])}")
    end

    # Its legend entry: colour dot + label + amount.
    def flow_legend_item(seg)
      content_tag(:span, class: "flex items-center gap-1.5 text-xs") do
        safe_join([
          content_tag(:span, "", class: "h-2.5 w-2.5 shrink-0 rounded-full", style: "background-color: #{seg[:color]}"),
          content_tag(:span, seg[:label], class: "text-base-content/60"),
          content_tag(:span, brl(seg[:cents]), class: "tabular-nums text-base-content/40")
        ])
      end
    end
end
