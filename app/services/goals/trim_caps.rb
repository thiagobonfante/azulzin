module Goals
  # The tightest active-goal trim cap per category (.plans/goals 06 §3) — a goal's trim is a
  # temporary tightening of the standing budget, surfaced through the SAME Budgets::Check. Returns
  # { category_id => { cap_cents:, goal_id:, goal_name: } } so the alert copy can name the meta.
  class TrimCaps
    def self.for(account)
      account.goals.active.each_with_object({}) do |goal, caps|
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
