module GoalsHelper
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
end
