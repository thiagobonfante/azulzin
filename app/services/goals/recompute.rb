module Goals
  # Rebuilds the 3 plans (or counter-offers) for a draft goal from its FROZEN baseline snapshot
  # (.plans/goals 01 §5) — deterministic, so what the draft screen renders is byte-identical to
  # what choose activates. Also used at choose time so no plan number is ever trusted from params.
  class Recompute
    def self.call(goal)
      PlanBuilder.call(
        profile:                   Profile.from_snapshot(goal.baseline),
        kind:                      goal.kind,
        target_cents:              goal.target_cents,
        starts_on:                 goal.starts_on || current_month,
        target_date:               goal.target_date,
        initial_saved_cents:       goal.initial_saved_cents,
        committed_elsewhere_cents: committed_elsewhere(goal),
        user_caps:                 goal.user_caps.to_h { |k, v| [ k.to_i, v.to_i ] }
      )
    end

    # Current-month first-of-month (SP) — the activation default when a draft has no starts_on yet.
    def self.current_month = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month

    # Money already promised to the account's OTHER active goals (07 §1.3 capacity contention).
    def self.committed_elsewhere(goal)
      goal.account.goals.active.where.not(id: goal.id).sum(:monthly_target_cents)
    end
  end
end
