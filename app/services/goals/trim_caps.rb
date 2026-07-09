module Goals
  # The tightest active-goal trim cap per category (.plans/goals 06 §3) — a goal's trim is a
  # temporary tightening of the standing budget, surfaced through the SAME Budgets::Check. Returns
  # { category_id => { cap_cents:, goal_id:, goal_name: } } so the alert copy can name the meta.
  # Month-aware (round 3 decision 2): only goals whose plan is in force for `month` (starts_on ≤
  # month) tighten it — the activation month's alerts keep the old budget. Kept even though
  # ApplyBudgetCuts now writes the caps into the stored budgets: it pins alerts at the cap when a
  # member manually raises the budget mid-goal, and it carries the goal attribution.
  class TrimCaps
    def self.for(account, month:)
      account.goals.active.where(starts_on: ..month.beginning_of_month).each_with_object({}) do |goal, caps|
        (goal.plan["cuts"] || []).each do |cut|
          cid = cut["category_id"]
          next unless cid
          cap = cut["cap_cents"].to_i
          if caps[cid].nil? || cap < caps[cid][:cap_cents]
            caps[cid] = { cap_cents: cap, goal_id: goal.id, goal_name: goal.name }
          end
        end
      end
    end
  end
end
