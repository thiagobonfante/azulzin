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
      @account.categories.kept.where.not(monthly_budget_cents: nil).filter_map do |category|
        budget = category.monthly_budget_cents
        spent  = actuals[category.id].to_i
        if spent * 100 >= budget * @breach_percent
          event("budget_breach", category, spent, budget)
        elsif spent * 100 >= budget * @warn_percent
          event("budget_warn", category, spent, budget)
        end
      end
    end

    private

    # payload snapshots name + integer cents so a later-deleted category still renders;
    # money is formatted at render time in the viewer's locale. left clamps at zero (a
    # user may set warn above 100%, and "faltam -R$ 20" helps no one).
    def event(kind, category, spent, budget)
      { kind: kind, subject: category, period_key: @month,
        payload: { category: category.name, spent_cents: spent, budget_cents: budget,
                   left_cents: [ budget - spent, 0 ].max } }
    end
  end
end
