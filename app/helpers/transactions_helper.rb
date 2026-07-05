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

  # Hand-rolled inline-SVG sparkline of per-month sobra (M−3 … M+3), zero JS. Each dot is a
  # link to that month — the sparkline IS the long-range month navigation. Theme CSS vars only.
  def monthly_flow_sparkline(user, month)
    months  = (-3..3).map { |o| month >> o }
    values  = months.map { |m| MonthSummary.new(user, m).remaining_cents }
    w, h, pad = 320, 48, 8
    min, max  = values.min, values.max
    span      = [ max - min, 1 ].max
    y_for = ->(v) { h - pad - (v - min).fdiv(span) * (h - 2 * pad) }
    x_for = ->(i) { pad + i * (w - 2 * pad).fdiv(months.size - 1) }
    pts   = values.each_index.map { |i| [ x_for.call(i), y_for.call(values[i]) ] }
    zero_y = (y_for.call(0) if min < 0 && max > 0)

    content_tag(:svg, class: "h-12 w-full", viewBox: "0 0 #{w} #{h}", preserveAspectRatio: "none",
                role: "img", "aria-label": t("transactions.hero.sparkline_label")) do
      parts = []
      if zero_y
        parts << tag.line(x1: pad, y1: zero_y, x2: w - pad, y2: zero_y,
                          stroke: "currentColor", "stroke-opacity": "0.2", "stroke-dasharray": "3 3")
      end
      parts << tag.polyline(points: pts.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(" "),
                            fill: "none", stroke: "var(--color-primary)", "stroke-width": "2")
      months.each_with_index do |m, i|
        x, y = pts[i]
        is_current = m == Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month
        fill = values[i] >= 0 ? "var(--color-primary)" : "var(--color-error)"
        opacity = m > Date.current ? "0.5" : "1"
        dot = tag.circle(cx: x.round(1), cy: y.round(1), r: (is_current ? 5 : 3), fill: fill,
                         "fill-opacity": opacity, stroke: (is_current ? "var(--color-base-100)" : "none"),
                         "stroke-width": (is_current ? 2 : 0))
        parts << content_tag(:a, dot, href: transactions_path(month: m.strftime("%Y-%m")),
                             "aria-label": l(m, format: :month_year))
      end
      safe_join(parts)
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
