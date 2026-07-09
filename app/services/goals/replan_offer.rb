module Goals
  # The two honest ways to reorganize a struggling purchase goal (.plans/goals round 4),
  # quoted from LIVE numbers — a fresh Analyzer profile, never the frozen baseline: the
  # household's reality moved, that's the whole point of replanning.
  #   extend    — keep the parcel, finish later (the default; founder's "jan/2027 → fev/2027")
  #   hold_date — keep the promised date, the parcel rises (hidden when live capacity can't
  #               fund it, or when it wouldn't finish earlier than extend anyway)
  # Every option carries a full PlanBuilder plan (cuts included) so applying is exactly a
  # re-activation. Returns nil when there is nothing to offer (not active / not purchase /
  # already at target / nothing feasible) — savings_rate goals have no date to move (v1).
  class ReplanOffer
    Option = Data.define(:mode, :plan, :target_date)
    Offer  = Data.define(:goal, :saved_cents, :promised_done_on, :options) do
      def option(mode) = options.find { |o| o.mode == mode }
    end

    def self.for(goal, as_of: Date.current.in_time_zone(TZ).to_date)
      new(goal, as_of:).offer
    end

    def initialize(goal, as_of:)
      @goal  = goal
      @as_of = as_of
    end

    def offer
      return nil unless @goal.active? && @goal.purchase? && @goal.monthly_target_cents.to_i.positive?
      return nil if saved >= @goal.target_cents   # done — Achieve owns this moment, not Replan
      options = [ extend_option, hold_date_option ].compact
      return nil if options.empty?
      Offer.new(goal: @goal, saved_cents: saved, promised_done_on: promised_done_on, options:)
    end

    private
      def saved     = @saved ||= Progress.new(@goal, as_of: @as_of).actual_cents
      def start     = @start ||= Recompute.start_month
      def remaining = @goal.target_cents - saved

      # Keep the current parcel → the honest finish is start + ⌈remaining/parcel⌉ months
      # (the same shape as Progress#projected_done_on, anchored on the new schedule).
      # Only offered when that finish actually slipped past the chosen plan's promise — an
      # on-plan (or freshly replanned) goal has nothing to extend, so the section disappears.
      # PlanBuilder gates feasibility and supplies today's cuts; its required monthly is the
      # MINIMUM for that date (≤ the parcel by construction) — the option pins the parcel the
      # user already knows, so "manter a parcela" means exactly that.
      def extend_option
        return nil if extend_date <= promised_done_on.beginning_of_month
        plan = feasible_plan(extend_date)
        return nil unless plan
        Option.new(mode: "extend", target_date: extend_date,
                   plan: plan.with(monthly_target_cents: @goal.monthly_target_cents,
                                   projected_done_on: extend_date))
      end

      # Keep the promised date → the parcel rises to ⌈remaining/months-left⌉. Only offered
      # when it actually beats extend and live capacity funds it (PlanBuilder gates).
      def hold_date_option
        date = @goal.target_date&.beginning_of_month
        return nil if date.nil? || date >= extend_date
        plan = feasible_plan(date)
        Option.new(mode: "hold_date", plan:, target_date: date) if plan
      end

      def extend_date = start >> Goals.ceil_div(remaining, @goal.monthly_target_cents)

      # A real PlanBuilder run against today's profile: recomendado holds the asked date, so
      # its monthly IS ⌈remaining/months⌉ and its cuts are today's honest trim map. Draft-time
      # user_caps are NOT carried — they were choices against a baseline that no longer exists.
      def feasible_plan(target_date)
        build = PlanBuilder.call(
          profile: profile, kind: "purchase", target_cents: @goal.target_cents,
          starts_on: start, target_date: target_date, initial_saved_cents: saved,
          committed_elsewhere_cents: Recompute.committed_elsewhere(@goal)
        )
        build.feasible? ? build.plans.find { |p| p.template == "recomendado" } : nil
      end

      def profile = @profile ||= Analyzer.call(@goal.account)

      # The frozen plan's promise (Goal#promised_done_on — shared with RiskScan's slip test,
      # so the alert and the offer can never disagree) — also the "antes: X" side of the copy.
      def promised_done_on = @goal.promised_done_on
  end
end
