module GoalsHelper
  # Goal-kind glyphs — Heroicons v2 outline, same inline-`currentColor` pattern as
  # CategoriesHelper::CATEGORY_ICON_PATHS (no emoji in UI chrome).
  GOAL_KIND_ICON_PATHS = {
    "purchase"     => "M3 3v1.5M3 21v-6m0 0 2.77-.693a9 9 0 0 1 6.208.682l.108.054a9 9 0 0 0 6.086.71l3.114-.732a48.524 48.524 0 0 1-.005-10.499l-3.11.732a9 9 0 0 1-6.085-.711l-.108-.054a9 9 0 0 0-6.208-.682L3 4.5M3 15V4.5",
    "savings_rate" => "M2.25 18 9 11.25l4.306 4.306a11.95 11.95 0 0 1 5.814-5.518l2.74-1.22m0 0-5.94-2.281m5.94 2.28-2.28 5.941"
  }.freeze

  def goal_kind_icon_tag(kind, css_class: "h-5 w-5")
    path = GOAL_KIND_ICON_PATHS.fetch(kind.to_s)
    content_tag(:svg, tag.path(d: path, "stroke-linecap": "round", "stroke-linejoin": "round"),
                class: css_class, xmlns: "http://www.w3.org/2000/svg", fill: "none",
                viewBox: "0 0 24 24", "stroke-width": "1.6", stroke: "currentColor", "aria-hidden": "true")
  end

  # Month options for the "when" select on Screen 1 — the next 60 months (min = next month),
  # value is the first-of-month ISO date, label localized ("dezembro de 2027" / "December 2027").
  def goal_month_options
    start = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month
    (1..60).map { |i| [ l(start >> i, format: :month_year), (start >> i).iso8601 ] }
  end

  # Progress/pace status → daisyUI badge + bar colors. Positive is azulzin BLUE, never green;
  # only at-risk/off-track go warning/error (02 §3).
  def goal_pace_badge_class(status)
    { "on_track" => "badge-primary", "at_risk" => "badge-warning",
      "off_track" => "badge-error", "insufficient_data" => "badge-ghost" }.fetch(status, "badge-ghost")
  end

  def goal_bar_class(status)
    { "at_risk" => "bg-warning", "off_track" => "bg-error" }.fetch(status, "bg-primary")
  end

  # How a purchase plan's projected date lands vs the asked date → copy key suffix.
  def goal_plan_margin(plan, goal)
    return :none unless goal.purchase? && plan.projected_done_on && goal.target_date
    done = plan.projected_done_on.beginning_of_month
    asked = goal.target_date.beginning_of_month
    return :ahead  if done < asked
    return :behind if done > asked
    :exact
  end

  # Percentage of a value against a target, clamped 0..100, for CSS bars.
  def goal_percent(part, whole)
    return 0 if whole.to_i <= 0
    [ [ (BigDecimal(part.to_i) / whole * 100).round, 0 ].max, 100 ].min
  end

  # "Guardado para meta" per savings account (round 3 decision 7): the bank-accounts page's
  # livre/reservado split. Mirrors Goals::Progress attribution EXACTLY — the initial head start
  # goes to initial_saved_bank_account_id; transfers group by destination since each goal's
  # counting_from anchor — so Σ over accounts == Σ Progress#actual for earmarked active goals.
  # Active goals only (a discardable draft must not label household money; achieved/abandoned
  # release the label — "guardado continua guardado", just no longer reserved). Integer cents,
  # request-memoized (the index renders one row per account).
  def goal_reserved_cents(bank_account)
    @goal_reserved_map ||= begin
      map = Hash.new(0)
      Current.account.goals.active.each do |goal|
        map[goal.initial_saved_bank_account_id] += goal.initial_saved_cents.to_i if goal.initial_saved_bank_account_id
        next if goal.starts_on.blank?   # mirrors Progress#saved_since_start's guard
        ids = goal.savings_account_ids
        next if ids.empty?
        Current.account.transactions.saved_into(ids)
               .where(billing_month: Goals::Progress.new(goal).counting_from..)
               .group(:transfer_to_bank_account_id).sum(:amount_cents)
               .each { |account_id, cents| map[account_id] += cents }
      end
      map
    end
    @goal_reserved_map[bank_account.id]
  end
end
