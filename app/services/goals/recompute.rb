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
        starts_on:                 goal.starts_on || start_month,
        target_date:               goal.target_date,
        initial_saved_cents:       goal.initial_saved_cents,
        committed_elsewhere_cents: committed_elsewhere(goal),
        user_caps:                 goal.user_caps.to_h { |k, v| [ k.to_i, v.to_i ] }
      )
    end

    # Current-month first-of-month (SP).
    def self.current_month = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month

    # Where a goal's schedule anchors: NEXT month's first day (round 3 decision 3) — drafts are
    # priced from it and Activate freezes it, so the displayed plan == the activated plan.
    def self.start_month = current_month >> 1

    # Money already promised to the account's OTHER active goals (07 §1.3 capacity contention).
    def self.committed_elsewhere(goal)
      goal.account.goals.active.where.not(id: goal.id).sum(:monthly_target_cents)
    end
  end
end
