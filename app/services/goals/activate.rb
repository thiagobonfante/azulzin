module Goals
  # Activates a draft goal (.plans/goals 01 §5, 07 §1.2): recompute the chosen plan from the frozen
  # baseline (tamper-proof — never trust a number from params), guard the draft→active transition
  # against double-submit, and — in the SAME transaction — create the "pay yourself first" savings
  # Commitment. Returns a Result; the caller renders the error key.
  class Activate
    Result = Data.define(:ok, :error) do
      def ok? = ok
    end

    def self.call(goal, template:, bank_account_id: nil, source_bank_account_id: nil, created_by: nil)
      new(goal, template:, bank_account_id:, source_bank_account_id:, created_by:).call
    end

    def initialize(goal, template:, bank_account_id:, source_bank_account_id:, created_by: nil)
      @goal = goal
      @template = template
      @bank_account_id = bank_account_id.presence
      @source_bank_account_id = source_bank_account_id.presence
      # Attribution for the savings commitment: the activator when given, else the goal's
      # creator — never nil (was: nil for every activated goal, WA and web).
      @created_by = created_by || goal.created_by
    end

    def call
      build = Recompute.call(@goal)
      return failure(:infeasible) unless build.feasible?
      plan = build.plans.find { |p| p.template == @template }
      return failure(:invalid_template) unless plan
      # A goal is ALWAYS linked to a savings commitment (round 3 decision 4): the transfer needs
      # both legs, so a missing caixinha, missing source, or source == caixinha blocks activation.
      return failure(:missing_caixinha) if @bank_account_id.blank? || @source_bank_account_id.blank? ||
                                           @source_bank_account_id.to_s == @bank_account_id.to_s
      # The instrument ids come from params and are written via update_all/create! (which skip
      # model validations), so whitelist them against THIS account here (tenancy + savings-kind).
      return failure(:not_savings) unless valid_caixinha?
      return failure(:invalid_source) unless valid_source?

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
          status: "active", activated_at: Time.current, starts_on: Recompute.start_month,
          monthly_target_cents: plan.monthly_target_cents, plan: plan.to_snapshot,
          bank_account_id: @bank_account_id, updated_at: Time.current
        ).positive?
      end

      def valid_caixinha? = @goal.account.bank_accounts.kept.savings.exists?(id: @bank_account_id)
      def valid_source?   = @goal.account.bank_accounts.kept.exists?(id: @source_bank_account_id)

      def at_active_cap?
        @goal.account.goals.active.where.not(id: @goal.id).count >= Goal::MAX_ACTIVE
      end

      # Caixinha + distinct source are guaranteed by the :missing_caixinha gate above — every
      # active goal carries its commitment. (Pre-round-3 goals may still be unlinked: Progress
      # keeps the all-savings fallback for them.)
      def create_savings_commitment(plan)
        @goal.account.commitments.create!(
          kind: "savings", goal: @goal, bank_account_id: @source_bank_account_id,
          amount_cents: plan.monthly_target_cents, name: @goal.name, created_by: @created_by,
          starts_on: @goal.starts_on, ends_on: commitment_end(plan),
          schedule_day: earliest_pay_day, schedule_kind: "fixed_day"
        )
      end

      # Purchase = a parcelado: n = ⌈remaining / parcel⌉ months, the last one at starts_on >> (n−1)
      # — anchored on the CHOSEN plan, not target_date (leve honestly finishes later, acelerado
      # earlier). savings_rate stays open-ended (fixo-like).
      def commitment_end(plan)
        return nil unless @goal.purchase?
        n = [ Goals.ceil_div([ @goal.target_cents - @goal.initial_saved_cents, 0 ].max, plan.monthly_target_cents), 1 ].max
        @goal.starts_on >> (n - 1)
      end

      def earliest_pay_day
        @goal.account.incomes.kept.active.map { |i| i.expected_on(@goal.starts_on).day }.min || 5
      end

      def failure(reason) = Result.new(ok: false, error: reason)
  end
end
