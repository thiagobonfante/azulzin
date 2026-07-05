module TransactionsHelper
  # The user's accounts/cards, loaded once per render for the instrument picker.
  def inbox_bank_accounts
    @inbox_bank_accounts ||= Current.user.bank_accounts.includes(:institution).order(:created_at)
  end

  def inbox_credit_cards
    @inbox_credit_cards ||= Current.user.credit_cards.includes(:institution).order(:created_at)
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

  # A flat fake chart is worse than none: only show the sparkline once there's a trajectory
  # to read (≥1 commitment/income, or ≥2 months of posted history).
  def show_sparkline?(user)
    user.commitments.exists? || user.incomes.exists? ||
      user.transactions.posted.distinct.count(:billing_month) >= 2
  end

  # Per-month sobra as a labeled diverging bar chart (M−3 … M+3), zero JS. Each column is a
  # link to that month (the chart IS the long-range navigation), captioned with the month and
  # emphasized for the current one; positive months read primary, negative read error, future
  # months dim. Bars are proportional to |sobra| around a shared zero line.
  def monthly_flow_chart(user, month)
    months  = (-3..3).map { |o| month >> o }
    values  = months.map { |m| MonthSummary.new(user, m).remaining_cents }
    today   = hub_today.beginning_of_month
    max_pos = values.select(&:positive?).max || 0
    max_neg = values.select(&:negative?).map(&:abs).max || 0
    span    = [ max_pos + max_neg, 1 ].max
    zero_top = max_pos.fdiv(span) * 100                 # % from top where zero sits
    straddles = max_pos.positive? && max_neg.positive?

    content_tag(:div, class: "flex items-stretch gap-1", role: "img",
                "aria-label": t("transactions.hero.sparkline_label")) do
      safe_join(months.each_with_index.map do |m, i|
        v          = values[i]
        is_current = m == today
        future     = m > today
        height_pct = v.zero? ? 0 : [ v.abs.fdiv(span) * 100, 3 ].max
        top_pct    = v.negative? ? zero_top : zero_top - height_pct
        bar_color  = bar_tone(v, current: is_current, future: future)

        bar_area = content_tag(:span, class: "relative block h-16 w-full") do
          parts = []
          parts << content_tag(:span, "", class: "absolute inset-x-0 border-t border-base-content/15",
                               style: "top: #{zero_top.round(1)}%") if straddles
          parts << content_tag(:span, "", class: "absolute inset-x-1 rounded-sm #{bar_color} #{'ring-2 ring-primary/30' if is_current}",
                               style: "top: #{top_pct.round(1)}%; height: #{height_pct.round(1)}%")
          safe_join(parts)
        end
        caption = content_tag(:span, l(m, format: "%b").capitalize,
                              class: "text-[10px] leading-none #{is_current ? 'font-semibold text-base-content/80' : 'text-base-content/40'}")

        link_to transactions_path(month: m.strftime("%Y-%m")),
                title: "#{l(m, format: :month_year)} · #{brl(v)}",
                class: "flex flex-1 flex-col items-center gap-1.5",
                aria: { label: l(m, format: :month_year) } do
          safe_join([ bar_area, caption ])
        end
      end)
    end
  end

  # Full literal Tailwind classes (JIT-safe) for a sobra bar: blue in the black, red under it,
  # dimmed for future months, full-strength for the current one.
  def bar_tone(value, current:, future:)
    if future     then value.negative? ? "bg-error/40" : "bg-primary/40"
    elsif current then value.negative? ? "bg-error"    : "bg-primary"
    else               value.negative? ? "bg-error/70" : "bg-primary/70"
    end
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

  # Direction glyph + tone for a ledger row.
  def ledger_row_glyph(txn)
    case txn.direction
    when "income"   then [ "↑", "text-success" ]
    when "transfer" then [ "⇄", "text-base-content/60" ]
    else                 [ "↓", "text-base-content/70" ]
    end
  end
end
