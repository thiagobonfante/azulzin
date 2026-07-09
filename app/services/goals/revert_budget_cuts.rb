module Goals
  # Restores the standing budgets ApplyBudgetCuts tightened, when a goal ends — on BOTH abandon
  # and achieve (round 3 decision 2: a goal's trim is a temporary tightening). Per category:
  # only when the stored value still equals the cap THIS goal applied (a manual re-edit since
  # apply always wins), restoring min(previous value, tightest cap among other active applied
  # goals) so ending goal A never loosens goal B's category. budgets_applied_at/previous_budgets
  # stay as audit trail — the callers' status-guarded flips prevent double-reverts.
  class RevertBudgetCuts
    def self.call(goal) = new(goal).call

    def initialize(goal)
      @goal = goal
    end

    def call
      return false if @goal.budgets_applied_at.blank?
      caps = own_caps
      @goal.previous_budgets.each do |category_id, prev|
        cap = caps[category_id.to_i]
        next unless cap&.positive?
        category = @goal.account.categories.kept.find_by(id: category_id)
        next unless category
        next unless category.monthly_budget_cents == cap
        restored = [ prev, remaining_caps[category.id] ].compact.min   # nil clears a created budget
        category.update_columns(monthly_budget_cents: restored, updated_at: Time.current)
      end
      true
    end

    private
      def own_caps
        (@goal.plan["cuts"] || []).to_h { |c| [ c["category_id"].to_i, c["cap_cents"].to_i ] }
      end

      # Tightest cap per category among OTHER still-active goals whose cuts were applied. The
      # caller flips this goal's status before reverting, so `active` naturally excludes it.
      def remaining_caps
        @remaining_caps ||= @goal.account.goals.active.where.not(id: @goal.id)
                                 .where.not(budgets_applied_at: nil)
                                 .each_with_object({}) do |goal, caps|
          (goal.plan["cuts"] || []).each do |cut|
            cid = cut["category_id"]
            cap = cut["cap_cents"].to_i
            next unless cid && cap.positive?
            caps[cid] = [ caps[cid], cap ].compact.min
          end
        end
      end
  end
end
