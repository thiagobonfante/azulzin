module Goals
  # The weekly guardian's deterministic status ladder (.plans/goals 03 §3, reduced by 06 §3 —
  # category overspend moved to Budgets::Check). Pure Postgres, ZERO LLM. Keeps pace + large-
  # purchase; achievement is handled by the job (it flips the goal). Findings are machine-readable
  # so the dashboard banner and (Phase 3) the WhatsApp push render from the same payload.
  class Checker
    Result = Data.define(:status, :findings, :expected_cents, :actual_cents)

    def self.call(goal, as_of: Date.current.in_time_zone(TZ).to_date)
      new(goal, as_of:).call
    end

    def initialize(goal, as_of:)
      @goal = goal
      @as_of = as_of
      @progress = Progress.new(goal, as_of:)
    end

    def call
      base = { expected_cents: expected, actual_cents: actual }
      return Result.new(status: "on_track", findings: [], **base) if in_grace?
      findings = [ pace_finding, big_purchase_finding ].compact
      Result.new(status: status_for(findings), findings:, **base)
    end

    private
      def actual   = @progress.actual_cents
      def expected = @progress.expected_cents

      # 2-week post-activation grace, extended to cover the pre-start gap month (round 3 decision
      # 3: the schedule only starts at starts_on) — no findings before max(activation+14d, start).
      def in_grace?
        return false unless @goal.activated_at
        @as_of < [ @goal.activated_at.in_time_zone(TZ).to_date + GRACE_DAYS, @goal.starts_on ].compact.max
      end

      # Guardado-vs-expected, never projected sobra; suppressed on a low-income month (01 §6).
      def pace_finding
        return nil unless @progress.pace_flag_allowed? && expected.positive?
        return nil unless actual * 100 < expected * PACE_AT_RISK_PCT
        { "finding" => "pace", "goal" => @goal.name,
          "expected_cents" => expected, "actual_cents" => actual, "gap_cents" => [ expected - actual, 0 ].max }
      end

      # A recent commitment-less expense ≥ max(3× category median, 20% of the monthly target).
      def big_purchase_finding
        floor = Goals.pct_of(@goal.monthly_target_cents.to_i, BIG_PURCHASE_TARGET_FRACTION)
        medians = baseline_medians
        txn = @goal.account.transactions.spend.where(commitment_id: nil)
                   .where(occurred_on: (@as_of - (BIG_PURCHASE_LOOKBACK_DAYS - 1))..@as_of)
                   .order(amount_cents: :desc)
                   .find { |t| threshold = [ medians[t.category_id].to_i * BIG_PURCHASE_MEDIAN_MULT, floor ].max
                               threshold.positive? && t.amount_cents >= threshold }
        return nil unless txn
        { "finding" => "big_purchase", "goal" => @goal.name,
          "amount_cents" => txn.amount_cents, "transaction_id" => txn.id }
      end

      def baseline_medians
        @baseline_medians ||= (@goal.baseline["categories"] || []).to_h { |c| [ c["category_id"], c["median_cents"].to_i ] }
      end

      # off_track's pace arm respects the irregular-income guard so a suppressed pace finding can
      # never yield an empty-findings off_track (every at_risk/off_track carries ≥1 finding).
      def status_for(findings)
        return "insufficient_data" if expected.zero? && actual.zero?
        pace_off = @progress.pace_flag_allowed? && expected.positive? && actual * 100 < expected * PACE_OFF_PCT
        return "off_track" if pace_off || findings.size >= 2
        return "at_risk" if findings.any?
        "on_track"
      end
  end
end
