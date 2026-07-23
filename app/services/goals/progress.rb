module Goals
  # Expected-vs-actual progress for an active goal (.plans/goals 01 §6) — shared by the show page,
  # dashboard widget, and weekly checker. Pace is ALWAYS guardado-vs-expected, never projected sobra
  # (contributing early lowers sobra; flagging a contributor for it is the banned self-defeating signal).
  # Expected is pay-schedule-aware so "at_risk on the 8th, salary on the 10th" never fires.
  class Progress
    def initialize(goal, as_of: Date.current.in_time_zone("America/Sao_Paulo").to_date)
      @goal  = goal
      @as_of = as_of
    end

    # initial head start + every posted transfer into the linked (or all) savings accounts since start.
    def actual_cents
      @goal.initial_saved_cents.to_i + saved_since_start
    end

    # monthly_target × full months elapsed + the pay-schedule-aware slice of the current month.
    # 0 through the whole pre-start gap (activation month, round 3 decision 3) — the MTD pro-rata
    # must never demand money before the schedule starts.
    def expected_cents
      return 0 unless @goal.starts_on && @goal.monthly_target_cents
      return 0 if current_month < @goal.starts_on.beginning_of_month
      monthly = @goal.monthly_target_cents
      monthly * full_months_elapsed + expected_mtd(monthly)
    end

    # Purchase goals conclude when the saved amount reaches the target (checked weekly + on render).
    def achieved? = @goal.purchase? && actual_cents >= @goal.target_cents

    # The posted transfers that count toward this goal, newest first — the show page's history.
    def contributions
      ids = @goal.savings_account_ids
      return @goal.account.transactions.none if ids.empty? || @goal.starts_on.blank?
      @goal.account.transactions.saved_into(ids)
           .where(billing_month: counting_from..)
           .order(occurred_on: :desc, id: :desc)
    end

    # Contributions count from the ACTIVATION month's begin while expected anchors on starts_on
    # (round 3 decision 3): an eager transfer in the gap month counts toward actual — "guardado
    # continua guardado" — without the schedule demanding anything before it starts. PUBLIC:
    # GoalsHelper#goal_reserved_cents mirrors this exact anchor so Σ reserved == Σ actual.
    def counting_from
      [ @goal.activated_at&.in_time_zone(Goals::TZ)&.to_date&.beginning_of_month,
        @goal.starts_on ].compact.min
    end

    # Derived completion forecast (round 3 decision 6) — "nesse ritmo, você chega em…". Purely
    # computed from remaining ÷ monthly, so an extra speed-up transfer pulls it earlier with no
    # writes; the frozen plan's projected_done_on stays honest as "the original plan".
    def projected_done_on
      return nil unless @goal.purchase? && @goal.monthly_target_cents.to_i.positive?
      remaining = @goal.target_cents - actual_cents
      return current_month if remaining <= 0
      current_month >> Goals.ceil_div(remaining, @goal.monthly_target_cents)
    end

    # Suppress pace findings when this month's income is < 70% of the baseline median — the shortfall
    # isn't behavior (irregular-income guard, 01 §6). No baseline income ⇒ always allowed.
    def pace_flag_allowed?
      base = @goal.baseline["median_income_cents"].to_i
      return true if base.zero?
      current_income_cents * 100 >= base * 70
    end

    private
      def saved_since_start
        ids = @goal.savings_account_ids   # linked caixinha only, else every savings account (01 §1)
        return 0 if ids.empty? || @goal.starts_on.blank?
        @goal.account.transactions.saved_into(ids)
             .where(billing_month: counting_from..)
             .sum(:amount_cents)
      end

      def current_month = @as_of.beginning_of_month

      def full_months_elapsed
        [ Goals.months_between(@goal.starts_on, current_month), 0 ].max
      end

      # 0 before the household's earliest expected payday this month, then linear pro-rata to month end.
      def expected_mtd(monthly)
        pay_day = earliest_pay_day
        day     = @as_of.day
        return 0 if day <= pay_day
        Goals.prorate(monthly, day - pay_day, @as_of.end_of_month.day - pay_day)
      end

      def earliest_pay_day
        days = @goal.account.incomes.kept.active.map { |i| i.expected_on(current_month).day }
        days.min || 1
      end

      def current_income_cents
        MonthSummary.new(@goal.account, current_month).incomes_cents
      end
  end
end
