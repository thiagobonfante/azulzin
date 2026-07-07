module BudgetsHelper
  # Budget-bar band color (up-tier 03 §6), at the viewer's own flat bands (D5): primary
  # (blue) under warn, warning (amber) in [warn, breach), error (red) at/over breach —
  # the same integer-cents comparison Budgets::Check alerts on, so bar and alert agree.
  def budget_bar_class(spent_cents, budget_cents, warn_percent:, breach_percent:)
    return "bg-error"   if spent_cents * 100 >= budget_cents * breach_percent
    return "bg-warning" if spent_cents * 100 >= budget_cents * warn_percent
    "bg-primary"
  end
end
