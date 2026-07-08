module Goals
  # Derives 3 fixed-personality plans (leve / recomendado / acelerado) from a frozen Profile, or
  # the three honest counter-offers when the goal doesn't close (.plans/goals 01 §5). Pure function
  # of its inputs — recomputing from the same baseline is byte-identical (choose-time tamper-proofing).
  # All math is integer cents + BigDecimal; every plan satisfies monthly_target == capacity_base + Σcuts.
  class PlanBuilder
    def self.call(profile:, kind:, target_cents:, starts_on:, target_date: nil,
                  initial_saved_cents: 0, committed_elsewhere_cents: 0)
      new(profile:, kind:, target_cents:, starts_on:, target_date:,
          initial_saved_cents:, committed_elsewhere_cents:).call
    end

    def initialize(profile:, kind:, target_cents:, starts_on:, target_date:,
                   initial_saved_cents:, committed_elsewhere_cents:)
      @profile = profile
      @kind = kind
      @target_cents = target_cents
      @starts_on = starts_on&.beginning_of_month
      @target_date = target_date&.beginning_of_month
      @initial_saved_cents = initial_saved_cents.to_i
      @committed_elsewhere_cents = committed_elsewhere_cents.to_i
    end

    def call
      if required <= max_achievable
        BuildResult.new(feasible: true,
                        plans: [leve, recomendado, acelerado],
                        counter_offers: nil,
                        capacity_base_cents: capacity_base, required_monthly_cents: required)
      else
        BuildResult.new(feasible: false, plans: [], counter_offers: counter_offers,
                        capacity_base_cents: capacity_base, required_monthly_cents: required)
      end
    end

    private
      def purchase? = @kind == "purchase"

      # The monthly amount the goal demands. Purchase: ⌈remaining / months⌉ (never undershoots).
      # savings_rate: save target_cents MORE than the household already puts away.
      def required
        @required ||=
          if purchase?
            Goals.ceil_div(remaining_target, [Goals.months_between(@starts_on, @target_date), 1].max)
          else
            @profile.median_guardado_cents + @target_cents
          end
      end

      def remaining_target = [@target_cents - @initial_saved_cents, 0].max

      # median(entradas − saidas − faturas) minus money already promised to other active goals
      # (07 §1.3 capacity contention) — a dream committed once can't be promised to a second.
      # NO floor: a genuinely negative disposable income (overspender or over-committed household)
      # must FAIL the feasibility gate and route to honest counter-offers, never be masked as R$0
      # — clamping would double-count cuts as net savings and freeze an unfundable commitment.
      def capacity_base
        @capacity_base ||= @profile.median_capacity_base_cents - @committed_elsewhere_cents
      end

      def trimmables = @profile.per_category_caps? ? @profile.trimmable_categories : []

      # The acelerado ceiling: capacity + every trimmable cut at its 40% max (floored at R$50).
      def max_achievable = @max_achievable ||= capacity_base + max_trims(trimmables, TRIM_PCT["acelerado"])

      def max_trims(cats, pct)
        cats.sum { |c| viable_cut(c, pct) }
      end

      def viable_cut(cat, pct)
        cut = Goals.pct_of(cat.trimmable_median_cents, pct)
        cut >= TRIM_FLOOR_CENTS ? cut : 0
      end

      # ---- the three personalities ----------------------------------------------------------

      # Leve: light touch — 15% off the top-3 trimmables, capped at required. The date may slip.
      def leve
        ceiling = capacity_base + max_trims(trimmables.first(LEVE_TOP_N), TRIM_PCT["leve"])
        plan("leve", target_contribution: [required, ceiling].min, pct: TRIM_PCT["leve"], candidates: trimmables.first(LEVE_TOP_N))
      end

      # Recomendado: hold the date — trim greedily (25% max each) until the required monthly is met.
      def recomendado
        plan("recomendado", target_contribution: required, pct: TRIM_PCT["recomendado"], candidates: trimmables)
      end

      # Acelerado: beat the date — push to required × 1.25, funded by up to 40% off each trimmable.
      def acelerado
        ceiling = capacity_base + max_trims(trimmables, TRIM_PCT["acelerado"])
        target = [Goals.pct_of(required, ACCELERADO_STRETCH), ceiling].min
        plan("acelerado", target_contribution: target, pct: TRIM_PCT["acelerado"], candidates: trimmables)
      end

      # When capacity alone covers the target the plan commits exactly the target (no cuts); when it
      # falls short, cuts fund the gap and the contribution is capacity + Σcuts (≤ target if trims run
      # out). Either way: Σcuts == max(0, monthly_target − capacity_base), cents-exact (01 §8 trap #3).
      def plan(template, target_contribution:, pct:, candidates:)
        gap = target_contribution - capacity_base
        if gap <= 0
          build_plan(template, target_contribution, [])
        else
          cuts = build_cuts(candidates, gap, pct)
          build_plan(template, capacity_base + cuts.sum(&:cut_cents), cuts)
        end
      end

      def build_plan(template, contribution, cuts)
        Plan.new(template:, monthly_target_cents: contribution, cuts:,
                 projected_done_on: done_on(contribution), buffer_cents: max_achievable - contribution)
      end

      # Greedy fill: take up to pct of each candidate's trimmable median (R$50 floor), the last cut
      # partial to land Σcuts exactly on `needed` — no rounding drift (01 §8 trap #3).
      def build_cuts(candidates, needed, pct)
        remaining = needed
        candidates.filter_map do |c|
          next if remaining <= 0
          max_cut = Goals.pct_of(c.trimmable_median_cents, pct)
          next if max_cut < TRIM_FLOOR_CENTS
          cut = [max_cut, remaining].min
          remaining -= cut
          Cut.new(category_id: c.category_id, name: c.name, baseline_cents: c.median_cents, cap_cents: c.median_cents - cut)
        end
      end

      def done_on(contribution)
        return nil unless purchase? && contribution.positive?
        @starts_on >> Goals.ceil_div(remaining_target, contribution)
      end

      # ---- infeasible: three deterministic ways out (02 §2.C) --------------------------------

      def counter_offers
        CounterOffers.new(
          required_monthly_cents: required,
          achievable_monthly_cents: max_achievable,
          feasible_date: feasible_date,
          feasible_target_cents: feasible_target,
          extra_income_cents: required - max_achievable
        )
      end

      def feasible_date
        return nil unless purchase? && max_achievable.positive?
        @starts_on >> Goals.ceil_div(remaining_target, max_achievable)
      end

      # For the asked date (purchase) the target you could actually hit; for savings_rate, the extra
      # per month you could realistically commit.
      def feasible_target
        if purchase?
          reachable = @initial_saved_cents + max_achievable * [Goals.months_between(@starts_on, @target_date), 1].max
          [reachable, @initial_saved_cents].max   # negative capacity can't erode the head start
        else
          [max_achievable - @profile.median_guardado_cents, 0].max
        end
      end
  end
end
