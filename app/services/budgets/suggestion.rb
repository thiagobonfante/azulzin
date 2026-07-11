module Budgets
  # The "no azul" nudge (up-tier 03 §5, D9): ZERO or ONE simplifying move — never a menu,
  # never bare praise. Priority order: (1) bank the surplus (almost always the right one),
  # else (2) right-size ONE chronically idle budget. Pure — returns one event hash or nil;
  # the job enforces the last-week window and the one-per-month rule across BOTH kinds
  # (the dedup index can't referee that alone: the kinds differ).
  class Suggestion
    # A "guardar" tap below this isn't a move, it's noise — R$ 50 minimum sobra.
    SURPLUS_FLOOR_CENTS = 5_000
    # "Budgeted well above" (03 §5.2) = budget ≥ 150% of the trailing-3-month median, with
    # all 3 months present — a young category never reads as chronically idle.
    RIGHTSIZE_FACTOR_PERCENT = 150

    def self.pick(account, month:) = new(account, month: month).pick

    def initialize(account, month:)
      @account = account
      @month   = month.beginning_of_month
    end

    # The whole thing is the "no azul" nudge: in the red, we say nothing at all — not even
    # a tidy-up (that would read as blame, exactly the tone 03 §5 bans).
    def pick
      return unless summary.in_the_blue?
      surplus_event || rightsize_event
    end

    private

    def summary = @summary ||= MonthSummary.new(@account, @month)

    # 03 §5.1 — a real sobra and somewhere to put it: same predicate + deep-link the hero's
    # "guardar" CTA already uses (first kept savings account, else the investment account —
    # destination_kind forks the copy: "guardar esse dindin" vs "conta investimento").
    def surplus_event
      return unless summary.remaining_cents >= SURPLUS_FLOOR_CENTS
      destination = @account.bank_accounts.kept.savings.first ||
                    @account.bank_accounts.kept.investment.first
      return unless destination
      { kind: "surplus_nudge", subject: nil, period_key: @month,
        payload: { surplus_cents: summary.remaining_cents, savings_account_id: destination.id,
                   destination_kind: destination.kind } }
    end

    # 03 §5.2 — the ONE budget lying hardest: full 3-month history, budget ≥ 1.5× median,
    # biggest budget-to-median gap wins. Framed as tidying, never as failure.
    def rightsize_event
      suggest = Suggest.new(@account, today: @month)
      idle = @account.categories.kept.where.not(monthly_budget_cents: nil).filter_map { |category|
        monthly = suggest.totals[category.id]
        next unless monthly&.size == Suggest::WINDOW_MONTHS
        median = suggest.medians[category.id]
        next unless category.monthly_budget_cents * 100 >= median * RIGHTSIZE_FACTOR_PERCENT
        [ category, median ]
      }.max_by { |category, median| category.monthly_budget_cents - median }
      return unless idle
      category, median = idle
      { kind: "rightsize_budget", subject: category, period_key: @month,
        payload: { category: category.name, budget_cents: category.monthly_budget_cents,
                   typical_cents: median } }
    end
  end
end
