module Goals
  # Derives 3 fixed-personality plans (leve / recomendado / acelerado) from a frozen Profile, or
  # the three honest counter-offers when the goal doesn't close (.plans/goals 01 §5). Pure function
  # of its inputs — recomputing from the same baseline is byte-identical (choose-time tamper-proofing).
  # All math is integer cents + BigDecimal; every plan satisfies
  # monthly_target == min(template_target, capacity_base) + Σcuts (with no user caps this reduces
  # to the original capacity_base + Σcuts ≥ monthly_target, cuts exactly funding the gap).
  #
  # user_caps ({ category_id => cap_cents }) are the household's own orçamento choices from the
  # Diagnóstico sliders: each becomes a FIXED cut carried in full by every plan (a cap is a
  # deliberate behavior change — its money is committed even past the template's own target, so
  # dragging a slider accelerates all three plans), and a capped category is off the table for
  # further template trims.
  class PlanBuilder
    def self.call(profile:, kind:, target_cents:, starts_on:, target_date: nil,
                  initial_saved_cents: 0, committed_elsewhere_cents: 0, user_caps: {})
      new(profile:, kind:, target_cents:, starts_on:, target_date:,
          initial_saved_cents:, committed_elsewhere_cents:, user_caps:).call
    end

    def initialize(profile:, kind:, target_cents:, starts_on:, target_date:,
                   initial_saved_cents:, committed_elsewhere_cents:, user_caps:)
      @profile = profile
      @kind = kind
      @target_cents = target_cents
      @starts_on = starts_on&.beginning_of_month
      @target_date = target_date&.beginning_of_month
      @initial_saved_cents = initial_saved_cents.to_i
      @committed_elsewhere_cents = committed_elsewhere_cents.to_i
      @user_caps = user_caps
    end

    def call
      if required <= max_achievable
        BuildResult.new(feasible: true,
                        plans: [ leve, recomendado, acelerado ],
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
      # savings_rate: target_cents is the TOTAL the household wants to put away each month.
      def required
        @required ||=
          if purchase?
            Goals.ceil_div(remaining_target, [ Goals.months_between(@starts_on, @target_date), 1 ].max)
          else
            @target_cents
          end
      end

      # savings_rate: the effort on top of what the household already puts away (≥ 0 — an
      # already-met target plans as pure habit-keeping, no cuts).
      def savings_extra = [ @target_cents - @profile.median_saved_cents, 0 ].max

      def remaining_target = [ @target_cents - @initial_saved_cents, 0 ].max

      # median(entradas − saidas − faturas) minus money already promised to other active goals
      # (07 §1.3 capacity contention) — a dream committed once can't be promised to a second.
      # NO floor: a genuinely negative disposable income (overspender or over-committed household)
      # must FAIL the feasibility gate and route to honest counter-offers, never be masked as R$0
      # — clamping would double-count cuts as net savings and freeze an unfundable commitment.
      def capacity_base
        @capacity_base ||= @profile.median_capacity_base_cents - @committed_elsewhere_cents
      end

      # Template trims only consider categories the user hasn't already capped themselves.
      def trimmables
        @trimmables ||= (@profile.per_category_caps? ? @profile.trimmable_categories : [])
                          .reject { |c| @user_caps.key?(c.category_id) }
      end

      # The user's own orçamento choices as fixed cuts, clamped to the category's trimmable slice
      # (the committed portion can't be cut). Only meaningful when per-category caps apply at all.
      def fixed_cuts = @fixed_cuts ||= build_fixed_cuts

      def build_fixed_cuts
        return [] unless @profile.per_category_caps?
        @profile.trimmable_categories.filter_map do |c|
          cap = @user_caps[c.category_id] or next
          cut = (c.median_cents - cap).clamp(0, c.trimmable_median_cents)
          next if cut <= 0
          Cut.new(category_id: c.category_id, name: c.name, baseline_cents: c.median_cents, cap_cents: c.median_cents - cut)
        end
      end

      def fixed_cut_cents = fixed_cuts.sum(&:cut_cents)

      # The acelerado ceiling: capacity + the user's fixed cuts + every remaining trimmable at its
      # 40% max (R$50 floor). User caps count in full — they're the household's own call.
      def max_achievable = @max_achievable ||= capacity_base + fixed_cut_cents + max_trims(trimmables, TRIM_PCT["acelerado"])

      def max_trims(cats, pct)
        cats.sum { |c| viable_cut(c, pct) }
      end

      def viable_cut(cat, pct)
        cut = Goals.pct_of(cat.trimmable_median_cents, pct)
        cut >= TRIM_FLOOR_CENTS ? cut : 0
      end

      # ---- the three personalities ----------------------------------------------------------

      # Leve: a genuinely lighter pace — 85% of the required effort, so the projected date honestly
      # slips (purchase) or the extra habit starts smaller (savings). Funded, when needed, by 15%
      # off the top-3 trimmables. Never collapses into recomendado just because the sobra covers it.
      def leve
        ceiling = capacity_base + fixed_cut_cents + max_trims(trimmables.first(LEVE_TOP_N), TRIM_PCT["leve"])
        plan("leve", target_contribution: [ eased_required, ceiling ].min,
             pct: TRIM_PCT["leve"], candidates: trimmables.first(LEVE_TOP_N))
      end

      # 85% of the effort: for a purchase that's 85% of the required monthly; for savings the ease
      # applies to the EXTRA only — leve must never plan below what the household already saves.
      def eased_required
        if purchase?
          [ Goals.pct_of(required, LEVE_EASE), 1 ].max
        else
          @profile.median_saved_cents + Goals.pct_of(savings_extra, LEVE_EASE)
        end
      end

      # Recomendado: hold the date — trim greedily (25% max each) until the required monthly is met.
      def recomendado
        plan("recomendado", target_contribution: required, pct: TRIM_PCT["recomendado"], candidates: trimmables)
      end

      # Acelerado: beat the date — push to required × 1.25, funded by up to 40% off each trimmable.
      def acelerado
        target = [ Goals.pct_of(required, ACCELERADO_STRETCH), max_achievable ].min
        plan("acelerado", target_contribution: target, pct: TRIM_PCT["acelerado"], candidates: trimmables)
      end

      # Each plan commits the sobra slice it needs (never more than capacity), every user cap in
      # full, and — only for the part still missing — template cuts, the last one partial so the
      # total lands cents-exact (01 §8 trap #3). Cap money the template didn't need is committed
      # anyway: a user cap is a deliberate behavior change, so dragging a slider accelerates every
      # plan. Invariant: monthly_target == min(template_target, capacity_base) + Σcuts.
      def plan(template, target_contribution:, pct:, candidates:)
        gap = target_contribution - capacity_base - fixed_cut_cents
        cuts = gap.positive? ? build_cuts(candidates, gap, pct) : []
        from_capacity = [ target_contribution, capacity_base ].min
        build_plan(template, from_capacity + fixed_cut_cents + cuts.sum(&:cut_cents), fixed_cuts + cuts)
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
          cut = [ max_cut, remaining ].min
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

      # For the asked date (purchase) the target you could actually hit; for savings_rate, the
      # monthly total the household could realistically put away.
      def feasible_target
        if purchase?
          reachable = @initial_saved_cents + max_achievable * [ Goals.months_between(@starts_on, @target_date), 1 ].max
          [ reachable, @initial_saved_cents ].max   # negative capacity can't erode the head start
        else
          [ max_achievable, 0 ].max
        end
      end
  end
end
