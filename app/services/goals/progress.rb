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
      @goal.initial_saved_cents.to_i + guardado_since_start
    end

    # monthly_target × full months elapsed + the pay-schedule-aware slice of the current month.
    def expected_cents
      return 0 unless @goal.starts_on && @goal.monthly_target_cents
      monthly = @goal.monthly_target_cents
      monthly * full_months_elapsed + expected_mtd(monthly)
    end

    # Purchase goals conclude when the saved amount reaches the target (checked weekly + on render).
    def achieved? = @goal.purchase? && actual_cents >= @goal.target_cents

    # Suppress pace findings when this month's income is < 70% of the baseline median — the shortfall
    # isn't behavior (irregular-income guard, 01 §6). No baseline income ⇒ always allowed.
    def pace_flag_allowed?
      base = @goal.baseline["median_income_cents"].to_i
      return true if base.zero?
      current_income_cents * 100 >= base * 70
    end

    private
      def guardado_since_start
        ids = savings_account_ids
        return 0 if ids.empty? || @goal.starts_on.blank?
        @goal.account.transactions.posted.kept
             .where(direction: "transfer", transfer_to_bank_account_id: ids)
             .where(billing_month: @goal.starts_on..)
             .sum(:amount_cents)
      end

      # Linked caixinha counts only its own transfers; unlinked counts every savings account (01 §1).
      def savings_account_ids
        return [@goal.bank_account_id] if @goal.bank_account_id
        @goal.account.bank_accounts.kept.savings.pluck(:id)
      end

      def current_month = @as_of.beginning_of_month

      def full_months_elapsed
        [Goals.months_between(@goal.starts_on, current_month), 0].max
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
        MonthSummary.new(@goal.account, current_month).entradas_cents
      end
  end
end
