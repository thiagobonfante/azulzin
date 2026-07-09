module Goals
  # Snapshots a household's spending baseline from its own ledger in one grouped round trip plus
  # three MonthSummary reads (.plans/goals 01 §4). Pure read; the frozen Profile is stored verbatim
  # in goals.baseline so plans recompute byte-identically and a later-deleted category still renders.
  class Analyzer
    def self.call(account, as_of: Date.current.in_time_zone("America/Sao_Paulo").to_date)
      new(account, as_of:).call
    end

    def initialize(account, as_of:)
      @account = account
      @as_of   = as_of
    end

    def call
      by_cat  = grouped_spend                                   # { category_id|nil => {total:{bm=>c}, trimmable:{bm=>c}} }
      summaries = window.map { |m| MonthSummary.new(@account, m) }

      Profile.new(
        sufficiency:                monthly_expense_counts.then { |c| sufficiency(c) },
        categories:                 category_stats(by_cat),
        median_income_cents:        Goals.median(summaries.map(&:entradas_cents)),
        median_capacity_base_cents: Goals.median(summaries.map { |ms| ms.entradas_cents - ms.saidas_cents - ms.faturas_cents }),
        median_guardado_cents:      Goals.median(summaries.map(&:guardado_cents)),
        income_irregular:           Goals.cv_squared(summaries.map(&:entradas_cents)) > INCOME_IRREGULAR_CV**2,
        uncategorized_ratio_bd:     uncategorized_ratio(by_cat),
        window:
      )
    end

    private
      # Trailing WINDOW_MONTHS full billing months, oldest → newest (excludes the current partial).
      def window
        @window ||= (1..WINDOW_MONTHS).map { |i| (@as_of.beginning_of_month << i) }.reverse
      end

      # One grouped query: per (category, month) the total spend and the trimmable (commitment-less)
      # portion — plans only ever cut the commitment_id IS NULL slice (01 §1).
      def grouped_spend
        rows = @account.transactions.spend
                       .where(billing_month: window)
                       .group(:category_id, :billing_month)
                       .pluck(:category_id, :billing_month,
                              Arel.sql("SUM(amount_cents)"),
                              Arel.sql("SUM(amount_cents) FILTER (WHERE commitment_id IS NULL)"))
        by_cat = Hash.new { |h, k| h[k] = { total: {}, trimmable: {} } }
        rows.each do |cat_id, bm, total, trimmable|
          by_cat[cat_id][:total][bm]     = total.to_i
          by_cat[cat_id][:trimmable][bm] = trimmable.to_i
        end
        by_cat
      end

      def category_stats(by_cat)
        cat_ids = by_cat.keys.compact
        cats = @account.categories.kept.where(id: cat_ids).index_by(&:id)
        cat_ids.filter_map do |cat_id|
          cat = cats[cat_id] or next   # deleted category → not trimmable, skip
          totals     = by_cat[cat_id][:total].values
          trimmables = by_cat[cat_id][:trimmable].values
          median     = Goals.median(totals)
          trim_med   = Goals.median(trimmables)
          CategoryStat.new(
            category_id: cat_id,
            name: cat.name,
            median_cents: median,
            trimmable_median_cents: trim_med,
            months_present: totals.size,
            flexibility: resolve_flexibility(cat, median, trim_med, totals)
          )
        end
      end

      # Tier-1 cached column → tier-2 seeded-name map → tier-3 deterministic (committed → essential,
      # else month-to-month variance tiebreak). The LLM classifier replaces tier-3 in Phase 4.
      def resolve_flexibility(cat, median, trim_med, monthly_totals)
        return cat.flexibility if cat.flexibility.present?
        mapped = NAME_FLEXIBILITY[cat.name.to_s.downcase]
        return mapped if mapped
        return "essential" if median.positive? && committed_ratio(median, trim_med) > COMMITTED_ESSENTIAL
        Goals.cv_squared(monthly_totals) > VARIANCE_FLEX_CV**2 ? "flexible" : "essential"
      end

      def committed_ratio(median, trim_med)
        return BigDecimal(0) if median.zero?
        BigDecimal(median - trim_med) / median
      end

      def monthly_expense_counts
        @account.transactions.spend.where(billing_month: window).group(:billing_month).count
      end

      # :ok ≥2 months with ≥10 posted expenses · :thin ≥1 month with any spend · :insufficient else.
      def sufficiency(counts)
        full = window.count { |m| counts[m].to_i >= MIN_EXPENSES_FOR_OK }
        return :ok if full >= 2
        window.any? { |m| counts[m].to_i.positive? } ? :thin : :insufficient
      end

      # Share of the trimmable spend that has no category — >40% flips the goal to total-cap-only.
      def uncategorized_ratio(by_cat)
        total = by_cat.sum { |_id, h| h[:trimmable].values.sum }
        return BigDecimal(0) if total.zero?
        uncat = (by_cat[nil] && by_cat[nil][:trimmable].values.sum).to_i
        BigDecimal(uncat) / total
      end
  end
end
