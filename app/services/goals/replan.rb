module Goals
  # Applies a ReplanOffer option (.plans/goals round 4) — the ONLY way a goal's plan is ever
  # rewritten, and always at the user's request (the guardian announces derived slips; it
  # never edits). Semantically a re-activation on today's numbers, in ONE transaction:
  #
  #   • initial_saved rebases to everything saved through LAST month (+ earmark on the goal's
  #     caixinha); the current month's transfers keep counting through the fresh window —
  #     Progress#actual_cents is INVARIANT across the rewrite (money-trap test).
  #   • activated_at := now and starts_on := next month — the schedule anchors exactly like a
  #     fresh activation, so grace + the gap month keep the guardian quiet through the switch.
  #   • the old savings commitment is archived (its paid parcels stay — history honest; the
  #     current month's unpaid occurrence disappears, which IS the founder's mid-month relief)
  #     and a new one is created with the new parcel, source account and payday carried over.
  #   • applied budget cuts revert NOW (against the OLD plan, before it's overwritten); the
  #     daily ApplyBudgetCutsJob writes the new plan's cuts when the new starts_on arrives.
  #
  # The option is RE-DERIVED here — no number from params is ever trusted (Activate's rule).
  class Replan
    MODES = %w[extend hold_date].freeze

    Result = Data.define(:ok, :error) do
      def ok? = ok
    end

    def self.call(goal, mode:) = new(goal, mode).call

    def initialize(goal, mode)
      @goal = goal
      @mode = mode.to_s
    end

    def call
      return failure(:invalid_mode) unless MODES.include?(@mode)
      applied = false
      ActiveRecord::Base.transaction do
        @goal.lock!   # serialize concurrent replans; also refreshes status
        offer  = ReplanOffer.for(@goal)
        option = offer&.option(@mode)
        next unless option
        RevertBudgetCuts.call(@goal)              # reads the OLD plan — must run before the rewrite
        # Unreachable while we hold the row lock (offer just verified active) — but a failed
        # guarded rewrite must roll the revert back with it, never commit alone.
        raise ActiveRecord::Rollback unless rewrite(option)
        swap_commitment(option)
        applied = true
      end
      applied ? Result.new(ok: true, error: nil) : failure(:unavailable)
    ensure
      @goal.reload if applied
    end

    private
      def start = @start ||= Recompute.start_month

      # Guarded on status (the Activate idiom): a goal abandoned/achieved mid-flight matches
      # zero rows. update_all skips validations — the DB checks still referee (initial ≥ 0,
      # monthly > 0, purchase has a date), and rebased < target holds because saved < target.
      def rewrite(option)
        rebased = rebased_initial
        Goal.where(id: @goal.id, status: "active").update_all(
          monthly_target_cents: option.plan.monthly_target_cents,
          target_date: option.target_date,
          starts_on: start,
          activated_at: Time.current,
          initial_saved_cents: rebased,
          initial_saved_bank_account_id: earmark_account_id(rebased),
          plan: option.plan.to_snapshot.merge(
            "replanned_on" => Date.current.in_time_zone(TZ).to_date.iso8601,
            "previous_monthly_target_cents" => @goal.monthly_target_cents,
            "previous_target_date" => @goal.target_date&.iso8601
          ),
          budgets_applied_at: nil, previous_budgets: {},
          updated_at: Time.current
        ).positive?
      end

      # Everything saved through LAST month folds into the head start; the current month's
      # transfers stay live in the new counting_from window (activated_at = now ⇒ this month's
      # begin) — counted once, on exactly one side of the boundary.
      def rebased_initial
        ids = savings_account_ids
        return @goal.initial_saved_cents.to_i if ids.empty?
        window = Progress.new(@goal).counting_from...Recompute.current_month
        @goal.initial_saved_cents.to_i +
          @goal.account.transactions.posted.kept
               .where(direction: "transfer", transfer_to_bank_account_id: ids)
               .where(billing_month: window)
               .sum(:amount_cents)
      end

      def savings_account_ids
        return [ @goal.bank_account_id ] if @goal.bank_account_id
        @goal.account.bank_accounts.kept.savings.pluck(:id)
      end

      # The merged head start lives in the goal's caixinha (an original head start in a
      # different caixinha can't keep a split pointer — the bulk anchors here). Legacy
      # unlinked goals keep whatever they had.
      def earmark_account_id(rebased)
        return @goal.initial_saved_bank_account_id unless rebased.positive? && @goal.bank_account_id
        @goal.bank_account_id
      end

      # Archive-and-recreate, the Activate shape: parcels restart at 0/n on the new schedule
      # while the old commitment keeps its paid history. Source account + payday carry over.
      # Legacy unlinked goals (no commitment) just get the goal rewrite.
      def swap_commitment(option)
        old = @goal.commitments.savings.kept.active.first
        @goal.commitments.savings.active.update_all(archived_at: Time.current, updated_at: Time.current)
        return unless old
        n = [ Goals.ceil_div(@goal.target_cents - rebased_full, option.plan.monthly_target_cents), 1 ].max
        @goal.account.commitments.create!(
          kind: "savings", goal: @goal, bank_account_id: old.bank_account_id,
          amount_cents: option.plan.monthly_target_cents, name: @goal.name,
          starts_on: start, ends_on: start >> (n - 1),
          schedule_day: old.schedule_day, schedule_kind: old.schedule_kind
        )
      end

      # Live remaining for the parcel count (mirrors Activate's target − initial shape, on
      # today's saved total — current-month transfers included).
      def rebased_full = Progress.new(@goal).actual_cents

      def failure(reason) = Result.new(ok: false, error: reason)
  end
end
