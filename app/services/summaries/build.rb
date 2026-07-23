module Summaries
  # F3's digest assembler (.plans/up-tier 04 §1): the weekly and monthly recaps, composed
  # ONLY from existing read models — MonthSummary, Budgets::Actuals, Reminders::Scan — so
  # a summary can never disagree with the hub (04 §4: no re-derivation). Pure: returns
  # { period_key:, payload: } for the caller to record per member, or nil when the period
  # has nothing to say (04 §4: zero activity + no upcoming bills ⇒ no row, no push —
  # never "semana parada").
  #
  # Payloads snapshot names + integer cents (nested items string-keyed, the JSONB shape).
  # Composite display lines (spent/cats, upcoming, budget) are assembled at RENDER time by
  # Summaries::Lines in each recipient's locale — money formatting and locale words like
  # "outros" are never baked into the stored snapshot.
  class Build
    WEEK_DAYS      = 7
    TOP_CATEGORIES = 3   # 04 §4: top-3 + "outros", never a wall
    UPCOMING_BILLS = 2   # next-2 bills in the weekly look-ahead
    LOOKAHEAD_DAYS = 7

    # as_of anchors the windows and period_keys — the dispatch jobs pass their SP "today"
    # so a delayed run still files under the dispatched week/month; the default covers
    # manual/console runs (Date.current is SP, the app TZ).
    def self.call(account, period, as_of: Date.current)
      case period
      when :weekly  then new(account, as_of: as_of).weekly
      when :monthly then new(account, as_of: as_of).monthly
      end
    end

    def initialize(account, as_of: Date.current)
      @account = account
      @today   = as_of
    end

    # Last 7 days of spend by category + month-to-date sobra + the next bills.
    # period_key = the week's Monday (SP-time), so a re-run dedupes into one row.
    def weekly
      spend    = spend_last_week
      upcoming = upcoming_bills
      return if spend.empty? && upcoming.empty?
      summary = MonthSummary.new(@account, @today.beginning_of_month)
      { period_key: @today.beginning_of_week(:monday),
        payload: { spent_cents: spend.values.sum,
                   surplus_cents: summary.remaining_cents,
                   upcoming: upcoming }.merge(category_snapshot(spend)) }
    end

    # Recaps the month just CLOSED — prior month relative to today SP-time (run on the
    # 1st; the SP boundary, not UTC's, decides which month that is). The full hub strip
    # plus budget performance when any budgets are set. period_key = that month's first.
    def monthly
      month   = @today.prev_month.beginning_of_month
      summary = MonthSummary.new(@account, month)
      return if summary.incomes_cents.zero? && summary.outflows_total_cents.zero? &&
                summary.saved_cents.zero?
      spend = Budgets::Actuals.for(@account, month, summary: summary)
      { period_key: month,
        payload: { month: month.iso8601,
                   in_cents:    summary.incomes_cents,
                   out_cents:   summary.expenses_cents,
                   bills_cents: summary.bills_cents,
                   surplus_cents: summary.remaining_cents,
                   saved_cents: summary.saved_cents }
                 .merge(category_snapshot(spend)).merge(budget_counts(spend)) }
    end

    private

    # The Budgets::Actuals query shape scoped to an occurred_on window (04 §1). Actuals
    # itself buckets by billing_month — the wrong lens for "what did you spend THIS week"
    # (a card purchase belongs to the week it happened, not the fatura's month) — and its
    # commitment projection is a month concept, so this stays a dedicated small query.
    def spend_last_week
      @account.transactions.spend.where(occurred_on: (@today - (WEEK_DAYS - 1))..@today)
              .group(:category_id).sum(:amount_cents)
    end

    # Top-3 named categories, biggest first; everything else (uncategorized included)
    # folds into a locale-neutral other_cents — "outros" is the renderer's word
    # (Summaries::Lines), never stored. Name lookup skips no one: a later-discarded
    # category still renders from this snapshot.
    def category_snapshot(spend)
      names = @account.categories.where(id: spend.keys.compact).pluck(:id, :name).to_h
      top = spend.filter_map { |id, cents| { "name" => names[id], "cents" => cents } if names[id] }
                 .sort_by { |cat| -cat["cents"] }.first(TOP_CATEGORIES)
      { top_categories: top, other_cents: spend.values.sum - top.sum { |cat| cat["cents"] } }
    end

    # The recap doubles as a look-ahead (04 §1): the next actual bills over
    # Reminders::Scan's window — a fatura closing isn't a payment, an expected income
    # isn't a bill, and the scan's behind-the-window overdue grace isn't "upcoming".
    def upcoming_bills
      Reminders::Scan.call(@account, from: @today, to: @today + LOOKAHEAD_DAYS)
        .select { |e| %w[bill_due card_due].include?(e[:kind]) }
        .sort_by { |e| e[:period_key] }
        .first(UPCOMING_BILLS)
        .map { |e| { "name" => e[:payload][:name] || e[:payload][:card], "cents" => e[:payload][:amount_cents] } }
    end

    # "dentro do combinado em N de M" — the same Actuals map vs the same standing budgets
    # Budgets::Check reads, so the digest can never disagree with the alerts. Omitted
    # entirely when no budgets are set (the template line skips). Within is STRICTLY
    # under: Budgets::Check fires budget_breach at spent >= budget (default 100% band),
    # so exactly-on-budget counts as blown here too.
    def budget_counts(spend)
      budgets = @account.categories.kept.where.not(monthly_budget_cents: nil)
                        .pluck(:id, :monthly_budget_cents)
      return {} if budgets.empty?
      { budget_within: budgets.count { |id, budget| spend[id].to_i < budget },
        budget_total: budgets.size }
    end
  end
end
