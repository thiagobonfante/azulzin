module Budgets
  # The deterministic "prevê" helper (up-tier 03 §3): per-category MEDIAN of the trailing
  # WINDOW_MONTHS full billing months — median, NEVER mean (one vet bill must not inflate
  # the suggestion: [400, 420, 4100] → 420). One grouped query; ≤3 points per category, so
  # the median is a trivial sort. Zero LLM, integer cents throughout.
  class Suggest
    WINDOW_MONTHS = 3

    # { category_id => median_cents } for every category with ≥1 full month of spend.
    def self.call(account) = new(account).medians

    def initialize(account, today: Date.current.in_time_zone("America/Sao_Paulo").to_date)
      @account = account
      @today   = today
    end

    def medians = totals.transform_values { |monthly| median(monthly) }

    # { category_id => [monthly total cents, ...] } over the trailing full billing months —
    # the current, partial month never contaminates the baseline.
    def totals
      @totals ||= begin
        months = (1..WINDOW_MONTHS).map { |i| @today.beginning_of_month << i }
        rows = @account.transactions.spend.where(billing_month: months)
                       .group(:billing_month, :category_id).sum(:amount_cents)
        rows.each_with_object({}) do |((_month, category_id), cents), acc|
          next if category_id.nil?   # uncategorized spend suggests nothing
          (acc[category_id] ||= []) << cents
        end
      end
    end

    private

    # Median of 1–3 integer totals, float-free: odd count → the middle; even count → the
    # integer mean of the middle two (cents, so the truncation is at most half a centavo).
    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end
  end
end
