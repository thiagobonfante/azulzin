# The deterministic goals engine (.plans/goals 01). Every number here is integer cents + BigDecimal
# — NO Float ever touches goal math (CI grep gate). This module holds the shared value objects,
# calibration constants, and cents-exact math helpers used by Analyzer / PlanBuilder / Progress.
module Goals
  WINDOW_MONTHS       = 3        # trailing full billing months for baselines (mirrors Budgets::Suggest)
  MIN_EXPENSES_FOR_OK = 10       # posted expenses/month for a month to count toward :ok sufficiency
  UNCATEGORIZED_LIMIT = BigDecimal("0.40")   # >40% of trimmable spend uncategorized → total-cap-only
  INCOME_IRREGULAR_CV = BigDecimal("0.35")   # income coefficient-of-variation irregularity threshold
  VARIANCE_FLEX_CV    = BigDecimal("0.40")   # tier-3 tiebreak: monthly-spend CV above this → flexible
  COMMITTED_ESSENTIAL = BigDecimal("0.50")   # tier-3: >50% of a category's spend committed → essential
  TRIM_FLOOR_CENTS    = 5_000    # R$50 — don't propose a cut smaller than this from a category's max
  TZ = "America/Sao_Paulo"

  # Weekly-checker calibration (.plans/goals 03 §3; tunable, justified by observed accuracy).
  PACE_AT_RISK_PCT = 95          # actual < 95% of expected guardado → at_risk pace finding
  PACE_OFF_PCT     = 80          # actual < 80% of expected → off_track
  GRACE_DAYS       = 14          # no findings in the first 2 weeks after activation
  BIG_PURCHASE_TARGET_FRACTION = BigDecimal("0.20")  # a purchase ≥ 20% of the monthly target trips…
  BIG_PURCHASE_MEDIAN_MULT     = 3                    # …or ≥ 3× the category's baseline median
  BIG_PURCHASE_LOOKBACK_DAYS   = 7

  # Per-template max trim fraction of a trimmable category's median (01 §5).
  TRIM_PCT = { "leve" => BigDecimal("0.15"), "recomendado" => BigDecimal("0.25"), "acelerado" => BigDecimal("0.40") }.freeze
  ACCELERADO_STRETCH = BigDecimal("1.25")   # acelerado targets up to required × 1.25
  LEVE_TOP_N = 3    # leve only trims the top-N trimmable categories, 15% each

  # Tier-1 flexibility name map (01 §1) covering the seeded defaults in BOTH locales, keyed by
  # downcased name. "Outros"/"Other" and custom names fall through to the deterministic tier-3.
  NAME_FLEXIBILITY = {
    "mercado" => "essential", "transporte" => "essential", "moradia" => "essential",
    "contas" => "essential", "saúde" => "essential", "educação" => "essential",
    "groceries" => "essential", "transport" => "essential", "housing" => "essential",
    "bills & utilities" => "essential", "health" => "essential", "education" => "essential",
    "restaurantes" => "flexible", "lazer" => "flexible", "assinaturas" => "flexible",
    "vestuário" => "flexible", "viagem" => "flexible",
    "dining out" => "flexible", "leisure" => "flexible", "subscriptions" => "flexible",
    "clothing" => "flexible", "travel" => "flexible",
  }.freeze

  # ---- Value objects (frozen; snapshotted verbatim into goals.baseline / goals.plan) --------

  CategoryStat = Data.define(:category_id, :name, :median_cents, :trimmable_median_cents, :months_present, :flexibility) do
    def flexible? = flexibility == "flexible"
  end

  Profile = Data.define(
    :sufficiency,                  # :ok | :thin | :insufficient
    :categories,                   # [CategoryStat]
    :median_income_cents,
    :median_capacity_base_cents,   # median(entradas − saidas − faturas) = sobra + guardado (synthesis #7)
    :median_guardado_cents,
    :income_irregular,             # boolean (CV > 0.35)
    :uncategorized_ratio_bd,       # BigDecimal share of trimmable spend that is uncategorized
    :window                        # [Date, Date, Date] window months (first-of-month)
  ) do
    def per_category_caps? = sufficiency != :insufficient && uncategorized_ratio_bd <= UNCATEGORIZED_LIMIT
    def trimmable_categories = categories.select(&:flexible?).sort_by { |c| -c.trimmable_median_cents }

    # Frozen jsonb snapshot for goals.baseline — string keys, no BigDecimal/Date/Symbol objects, so
    # a recompute from the stored baseline is byte-identical to what was rendered (01 §5 tamper-proof).
    def to_snapshot
      {
        "sufficiency" => sufficiency.to_s,
        "categories" => categories.map { |c|
          { "category_id" => c.category_id, "name" => c.name, "median_cents" => c.median_cents,
            "trimmable_median_cents" => c.trimmable_median_cents, "months_present" => c.months_present,
            "flexibility" => c.flexibility }
        },
        "median_income_cents" => median_income_cents,
        "median_capacity_base_cents" => median_capacity_base_cents,
        "median_guardado_cents" => median_guardado_cents,
        "income_irregular" => income_irregular,
        "uncategorized_ratio_bd" => uncategorized_ratio_bd.to_s("F"),
        "window" => window.map(&:iso8601)
      }
    end

    def self.from_snapshot(h)
      new(
        sufficiency: h["sufficiency"].to_sym,
        categories: h["categories"].map { |c|
          CategoryStat.new(category_id: c["category_id"], name: c["name"], median_cents: c["median_cents"],
                           trimmable_median_cents: c["trimmable_median_cents"], months_present: c["months_present"],
                           flexibility: c["flexibility"])
        },
        median_income_cents: h["median_income_cents"],
        median_capacity_base_cents: h["median_capacity_base_cents"],
        median_guardado_cents: h["median_guardado_cents"],
        income_irregular: h["income_irregular"],
        uncategorized_ratio_bd: BigDecimal(h["uncategorized_ratio_bd"]),
        window: h["window"].map { |d| Date.iso8601(d) }
      )
    end
  end

  Cut = Data.define(:category_id, :name, :baseline_cents, :cap_cents) do
    def cut_cents = baseline_cents - cap_cents
  end

  Plan = Data.define(:template, :monthly_target_cents, :cuts, :projected_done_on, :buffer_cents) do
    def total_cut_cents = cuts.sum(&:cut_cents)

    # Frozen jsonb snapshot for goals.plan (01 §3) — category names copied so a deleted category
    # still renders. String keys, no Date/Data objects.
    def to_snapshot
      {
        "template" => template,
        "monthly_target_cents" => monthly_target_cents,
        "cuts" => cuts.map { |c|
          { "category_id" => c.category_id, "name" => c.name,
            "baseline_cents" => c.baseline_cents, "cap_cents" => c.cap_cents }
        },
        "projected_done_on" => projected_done_on&.iso8601,
        "buffer_cents" => buffer_cents
      }
    end
  end

  # The honest way out when a goal doesn't close (01 §5, 02 §2.C). All cents exact.
  CounterOffers = Data.define(:required_monthly_cents, :achievable_monthly_cents,
                              :feasible_date, :feasible_target_cents, :extra_income_cents)

  # PlanBuilder result: exactly one of plans / counter_offers is populated. capacity_base and
  # required are carried so the Diagnóstico strip and the feasibility property test can read them.
  BuildResult = Data.define(:feasible, :plans, :counter_offers, :capacity_base_cents, :required_monthly_cents) do
    def feasible? = feasible
  end

  module_function

  # Median of integer cents, mirroring Budgets::Suggest#median (even count → integer mean of the
  # middle two, truncation ≤ half a centavo). Returns 0 for an empty set.
  def median(values)
    return 0 if values.empty?
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  end

  # cents × num / den, ONE documented rounding rule: BigDecimal then round half-up. Integer out.
  def prorate(cents, num, den)
    return 0 if den.zero?
    (BigDecimal(cents) * num / den).round(0, half: :up).to_i
  end

  # ⌈(numerator) / den⌉ in exact integer cents — required-monthly never undershoots (01 §1, trap #2).
  def ceil_div(numerator, den)
    return 0 if den <= 0
    (BigDecimal(numerator) / den).ceil.to_i
  end

  def pct_of(cents, fraction_bd)
    (BigDecimal(cents) * fraction_bd).round(0, half: :up).to_i
  end

  # Whole-month distance a→b (both first-of-month), ≥ 0. Jul'26 → Dec'27 = 17.
  def months_between(from, to)
    (to.year * 12 + to.month) - (from.year * 12 + from.month)
  end

  # Squared coefficient of variation (variance / mean²) in BigDecimal — no sqrt, no Float. Compare
  # against a squared threshold (e.g. 0.35² = 0.1225) to judge irregularity without leaving integers.
  def cv_squared(values)
    return BigDecimal(0) if values.empty?
    n = values.size
    sum = values.sum
    return BigDecimal(0) if sum.zero?
    mean = BigDecimal(sum) / n
    variance = values.sum(BigDecimal(0)) { |x| (BigDecimal(x) - mean)**2 } / n
    variance / (mean * mean)
  end
end
