module Goals
  # Activates a draft goal (.plans/goals 01 §5, 07 §1.2): recompute the chosen plan from the frozen
  # baseline (tamper-proof — never trust a number from params), guard the draft→active transition
  # against double-submit, and — in the SAME transaction — create the "pay yourself first" savings
  # Commitment. Returns a Result; the caller renders the error key.
  class Activate
    Result = Data.define(:ok, :error) do
      def ok? = ok
    end

    def self.call(goal, template:, bank_account_id: nil, source_bank_account_id: nil)
      new(goal, template:, bank_account_id:, source_bank_account_id:).call
    end

    def initialize(goal, template:, bank_account_id:, source_bank_account_id:)
      @goal = goal
      @template = template
      @bank_account_id = bank_account_id.presence
      @source_bank_account_id = source_bank_account_id.presence
    end

    def call
      build = Recompute.call(@goal)
      return failure(:infeasible) unless build.feasible?
      plan = build.plans.find { |p| p.template == @template }
      return failure(:invalid_template) unless plan
      # The instrument ids come from params and are written via update_all/create! (which skip
      # model validations), so whitelist them against THIS account here (tenancy + savings-kind).
      return failure(:not_savings) if @bank_account_id && !valid_caixinha?
      return failure(:invalid_source) if @source_bank_account_id && !valid_source?

      # with_lock serializes activations per account so the cap check + flip are one critical
      # section (guarded_update alone can't referee a count across two different drafts).
      @goal.account.with_lock do
        return failure(:too_many_active) if at_active_cap?
        return failure(:not_draft) unless guarded_activate(plan)
        @goal.reload
        create_savings_commitment(plan)
      end
      Result.new(ok: true, error: nil)
    end

    private
      # Conditional draft→active transition (Transaction#guarded_update pattern) — a double-submit
      # can't activate twice with different plans; the second update matches zero rows.
      def guarded_activate(plan)
        Goal.where(id: @goal.id, status: "draft").update_all(
          status: "active", activated_at: Time.current, starts_on: Recompute.current_month,
          monthly_target_cents: plan.monthly_target_cents, plan: plan.to_snapshot,
          bank_account_id: @bank_account_id, updated_at: Time.current
        ).positive?
      end

      def valid_caixinha? = @goal.account.bank_accounts.kept.savings.exists?(id: @bank_account_id)
      def valid_source?   = @goal.account.bank_accounts.kept.exists?(id: @source_bank_account_id)

      def at_active_cap?
        @goal.account.goals.active.where.not(id: @goal.id).count >= Goal::MAX_ACTIVE
      end

      # Only when the goal is linked to a caixinha AND a distinct funding source is chosen — the
      # transfer needs both legs. Unlinked goals fall back to all-savings progress with no commitment.
      def create_savings_commitment(plan)
        return unless @bank_account_id && @source_bank_account_id && @source_bank_account_id.to_s != @bank_account_id.to_s

        @goal.account.commitments.create!(
          kind: "savings", goal: @goal, bank_account_id: @source_bank_account_id,
          amount_cents: plan.monthly_target_cents, name: @goal.name,
          starts_on: @goal.starts_on, ends_on: commitment_end,
          schedule_day: earliest_pay_day, schedule_kind: "fixed_day"
        )
      end

      def commitment_end = @goal.purchase? ? @goal.target_date.beginning_of_month : nil

      def earliest_pay_day
        @goal.account.incomes.kept.active.map { |i| i.expected_on(@goal.starts_on).day }.min || 5
      end

      def failure(reason) = Result.new(ok: false, error: reason)
  end
end
