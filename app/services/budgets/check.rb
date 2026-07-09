module Budgets
  # The warn/breach sweep body (up-tier 03 §4): for one billing month, compare each
  # budgeted category's actual (Budgets::Actuals — the exact map the hero bar renders) to
  # its standing budget at the MEMBER's flat bands (D5: flat, never prorated — "orçamento
  # de R$ 600" is a monthly number to a person). Breach wins: at/over breach_percent the
  # event is budget_breach; budget_warn only inside [warn, breach).
  #
  # Pure — returns event hashes shaped for Notification.record! (the Reminders::Scan
  # idiom); the caller records them per member. period_key = the billing month and the
  # kind is in the dedup key, so crossing 80 then later 100 fires two rows over time,
  # re-crossing the same band is silent, and a new month re-arms both.
  class Check
    def self.call(account, month:, warn_percent:, breach_percent:)
      new(account, month: month, warn_percent: warn_percent, breach_percent: breach_percent).call
    end

    def initialize(account, month:, warn_percent:, breach_percent:)
      @account        = account
      @month          = month.beginning_of_month
      @warn_percent   = warn_percent
      @breach_percent = breach_percent
    end

    def call
      actuals = Actuals.for(@account, @month)
      trims   = Goals::TrimCaps.for(@account, month: @month)   # a goal trim temporarily tightens the standing budget (goals 06 §3)
      budgeted(trims).filter_map do |category|
        limit, goal = effective_limit(category.monthly_budget_cents, trims[category.id])
        next unless limit&.positive?
        spent = actuals[category.id].to_i
        if spent * 100 >= limit * @breach_percent
          event("budget_breach", category, spent, limit, goal)
        elsif spent * 100 >= limit * @warn_percent
          event("budget_warn", category, spent, limit, goal)
        end
      end
    end

    private

    # Categories with a standing budget OR an active-goal trim cap.
    def budgeted(trims)
      @account.categories.kept.where("monthly_budget_cents IS NOT NULL OR id IN (?)", trims.keys.presence || [ 0 ])
    end

    # The binding limit = min(standing budget, goal trim cap) — either may be nil. The goal is
    # returned only when its trim is the tightest limit, so the copy names the meta.
    def effective_limit(budget, trim)
      candidates = [ budget, trim&.dig(:cap_cents) ].compact
      return [ nil, nil ] if candidates.empty?
      limit = candidates.min
      [ limit, (trim if trim && trim[:cap_cents] == limit) ]
    end

    # payload snapshots name + integer cents so a later-deleted category still renders;
    # money is formatted at render time in the viewer's locale. left clamps at zero (a
    # user may set warn above 100%, and "faltam -R$ 20" helps no one). When a goal trim
    # binds, goal_id/goal_name join the payload and template_key forks to the _goal copy.
    def event(kind, category, spent, limit, goal)
      payload = { category: category.name, spent_cents: spent, budget_cents: limit,
                  left_cents: [ limit - spent, 0 ].max }
      payload.merge!(goal_id: goal[:goal_id], goal_name: goal[:goal_name]) if goal
      { kind: kind, subject: category, period_key: @month, payload: payload }
    end
  end
end
