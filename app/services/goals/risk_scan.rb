module Goals
  # The weekly guardian's predictive arm (.plans/goals round 4): account-level risk findings,
  # computed ONCE per sweep and attached to specific goals, merged into the Checker result by
  # NotifyMemberJob. Pure Postgres + MonthSummary — ZERO LLM. Findings:
  #   red_month      — this month's projection closes in the red while goal parcels sit in it
  #   next_month_red — next month's projection breaks (faturas already carry posted card spend
  #                    billing next month — the "cartão sempre cai no mês que vem" case)
  #   budget_raised  — a standing budget was raised above an applied goal cap; TrimCaps still
  #                    pins the spend alerts, this warns that the INTENT breaks the goal's math
  #   missed_month   — last month's contributions came in under the parcel; carries the derived
  #                    new finish date (the frozen plan is never rewritten here) plus a
  #                    deterministic "what went wrong" cause with the empathy fork (essential
  #                    category / lower income → gentle variant)
  # red/next/missed are "urgent": NotifyMemberJob lets them bypass the 14-day cooldown (never
  # the delta-gate or the weekly WA cap). Returns { goal_id => [finding hashes] }.
  class RiskScan
    CAUSE_FLOOR_CENTS = 5_000   # don't name a cause for an overage under R$ 50
    LOW_INCOME_PCT    = 70      # mirrors Progress#pace_flag_allowed?

    def self.call(account, as_of:) = new(account, as_of:).call

    def initialize(account, as_of:)
      @account = account
      @as_of   = as_of
      @month   = as_of.beginning_of_month
    end

    def call
      @findings = Hash.new { |h, k| h[k] = [] }
      return @findings if goals.empty?
      scan_red(@month, "red_month")
      scan_red(@month >> 1, "next_month_red")
      scan_missed_month
      scan_budget_raised
      @findings
    end

    private
      def goals = @goals ||= @account.goals.active.to_a

      # ---- red projections ---------------------------------------------------------------

      # Fires only when goal parcels sit in that month (otherwise it's generic household
      # trouble — the budget/summary kinds' story, not a goals alert) and attaches to the
      # goal with the largest occurrence, so one red month = ONE alert, not one per goal.
      def scan_red(month, finding)
        committed = committed_by_goal(month)
        return if committed.empty?
        summary = MonthSummary.new(@account, month)
        remaining = summary.remaining_cents
        return unless remaining.negative?
        goal_id = committed.max_by { |_, cents| cents }.first
        payload = { "finding" => finding, "goal" => goals_by_id[goal_id].name,
                    "month" => month.iso8601, "shortfall_cents" => -remaining, "urgent" => true }
        payload["committed_cents"] = committed.values.sum if finding == "red_month"
        payload["faturas_cents"]   = summary.faturas_cents if finding == "next_month_red"
        @findings[goal_id] << payload
      end

      # { goal_id => this month's parcel } from the live savings commitments (legacy unlinked
      # goals have none — their red months can't be attributed to a parcel, pace still watches).
      def committed_by_goal(month)
        savings_commitments.each_with_object({}) do |commitment, map|
          map[commitment.goal_id] = commitment.amount_cents if commitment.active_in?(month)
        end
      end

      def savings_commitments
        @savings_commitments ||= @account.commitments.kept.active.savings
                                         .where(goal_id: goals_by_id.keys).to_a
      end

      def goals_by_id = @goals_by_id ||= goals.index_by(&:id)

      # ---- missed month --------------------------------------------------------------------

      # Purchase goals whose schedule was in force last month and got less than the parcel.
      # Fires only when the derived finish actually slips past the chosen plan's promise —
      # a caught-up or rounding-neutral miss stays silent (pace covers the rest). The finding
      # announces the DERIVED date; the formal rewrite only happens through Replan.
      def scan_missed_month
        prev = @month << 1
        goals.each do |goal|
          next unless goal.purchase? && goal.monthly_target_cents.to_i.positive?
          next if goal.starts_on.nil? || goal.starts_on.beginning_of_month > prev
          saved = contributions_in(goal, prev)
          next unless saved < goal.monthly_target_cents
          projected = Progress.new(goal, as_of: @as_of).projected_done_on
          promised  = plan_done_on(goal)
          next unless projected && promised && projected > promised
          @findings[goal.id] << {
            "finding" => "missed_month", "goal" => goal.name, "month" => prev.iso8601,
            "expected_cents" => goal.monthly_target_cents, "saved_cents" => saved,
            "gap_cents" => goal.monthly_target_cents - saved,
            "old_month" => promised.iso8601, "new_month" => projected.iso8601, "urgent" => true
          }.merge(cause_for(goal, prev))
        end
      end

      # Transfers into the goal's caixinha that month — the exact Progress/guardado shape.
      def contributions_in(goal, month)
        ids = goal.bank_account_id ? [ goal.bank_account_id ] : all_savings_ids
        return 0 if ids.empty?
        @account.transactions.posted.kept
                .where(direction: "transfer", transfer_to_bank_account_id: ids)
                .where(billing_month: month)
                .sum(:amount_cents)
      end

      def all_savings_ids = @all_savings_ids ||= @account.bank_accounts.kept.savings.pluck(:id)

      # The chosen plan's promised finish (leve honestly finishes later than the asked date, so
      # the promise — not target_date — is the baseline for "it slipped").
      def plan_done_on(goal)
        iso = goal.plan["projected_done_on"]
        iso.present? ? Date.iso8601(iso) : goal.target_date
      end

      # "Where things went wrong", deterministically: lower income first (the gentlest truth),
      # then the worst category overage vs the goal's frozen baseline medians. The variant picks
      # the template tone: essential category / income → gentle, flexible → matter-of-fact.
      def cause_for(goal, month)
        base_income = goal.baseline["median_income_cents"].to_i
        if base_income.positive? && MonthSummary.new(@account, month).entradas_cents * 100 < base_income * LOW_INCOME_PCT
          return { "variant" => "income" }
        end
        category, over = worst_overage(goal, month)
        return { "variant" => "plain" } unless category
        cause = { "category" => category["name"], "over_cents" => over }
        cause["variant"] = "essential" if category["flexibility"] == "essential"
        cause
      end

      def worst_overage(goal, month)
        actuals = Budgets::Actuals.for(@account, month)
        worst = (goal.baseline["categories"] || []).filter_map { |cat|
          next unless cat["category_id"] && cat["median_cents"].to_i.positive?
          over = actuals[cat["category_id"]].to_i - cat["median_cents"].to_i
          [ cat, over ] if over >= CAUSE_FLOOR_CENTS
        }.max_by(&:last)
        worst || [ nil, nil ]
      end

      # ---- budget raised above an applied goal cap -------------------------------------------

      # Only after the write-through landed (budgets_applied_at) — before it, standing budgets
      # are legitimately higher. Names the worst offender; the delta-gate key carries its
      # category_id so a later different raise re-alerts. A budget cleared to nil is left to
      # TrimCaps' pinned alerts (deliberate v1 cut).
      def scan_budget_raised
        applied = goals.select { |g| g.budgets_applied_at.present? }
        return if applied.empty?
        categories = @account.categories.kept
                             .where(id: applied.flat_map { |g| (g.plan["cuts"] || []).map { |c| c["category_id"] } }.compact)
                             .index_by(&:id)
        applied.each do |goal|
          worst = (goal.plan["cuts"] || []).filter_map { |cut|
            category = categories[cut["category_id"]]
            cap = cut["cap_cents"].to_i
            next unless category&.monthly_budget_cents && cap.positive?
            over = category.monthly_budget_cents - cap
            [ category, cap, over ] if over.positive?
          }.max_by(&:last)
          next unless worst
          category, cap, over = worst
          @findings[goal.id] << {
            "finding" => "budget_raised", "goal" => goal.name,
            "category" => category.name, "category_id" => category.id,
            "budget_cents" => category.monthly_budget_cents, "cap_cents" => cap, "over_cents" => over
          }
        end
      end
  end
end
