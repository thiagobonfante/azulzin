require "test_helper"

# PlanBuilder is a pure function of a frozen Profile (.plans/goals 01 §5). These cover the
# feasibility gate, the three honest counter-offers, cents-exact trims (trap #3), and choose-time
# recompute determinism.
class Goals::PlanBuilderTest < ActiveSupport::TestCase
  # profile with the given capacity and flexible trimmable categories (all trimmable == median).
  def profile(capacity:, guardado: 0, income: 920_000, trimmables: {}, sufficiency: :ok)
    cats = trimmables.map.with_index do |(name, cents), i|
      Goals::CategoryStat.new(category_id: i + 1, name: name, median_cents: cents,
                              trimmable_median_cents: cents, months_present: 3, flexibility: "flexible")
    end
    Goals::Profile.new(sufficiency:, categories: cats, median_income_cents: income,
                       median_capacity_base_cents: capacity, median_guardado_cents: guardado,
                       income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
                       window: [Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1)])
  end

  def build(profile, **kw)
    Goals::PlanBuilder.call(profile:, kind: "purchase", target_cents: 6_000_000,
                            starts_on: Date.new(2026, 7, 1), target_date: Date.new(2027, 12, 1), **kw)
  end

  test "feasible goal yields exactly 3 plans and no counter-offers" do
    r = build(profile(capacity: 320_000, trimmables: { "Restaurantes" => 62_000, "Lazer" => 40_000 }))
    assert r.feasible?
    assert_equal %w[leve recomendado acelerado], r.plans.map(&:template)
    assert_nil r.counter_offers
  end

  test "required-monthly is ⌈remaining / months⌉ (hand-verified)" do
    r = build(profile(capacity: 400_000, trimmables: { "Restaurantes" => 200_000 }))
    assert_equal Goals.ceil_div(6_000_000, 17), r.required_monthly_cents   # 352_942
  end

  test "initial_saved reduces the required monthly" do
    r = build(profile(capacity: 400_000, trimmables: { "Restaurantes" => 200_000 }), initial_saved_cents: 1_000_000)
    assert_equal Goals.ceil_div(5_000_000, 17), r.required_monthly_cents
  end

  test "every feasible plan satisfies capacity_base + Σcuts ≥ monthly_target (exact)" do
    r = build(profile(capacity: 300_000, trimmables: { "Restaurantes" => 90_000, "Lazer" => 60_000, "Viagem" => 40_000 }))
    assert r.feasible?
    r.plans.each do |pl|
      assert_operator r.capacity_base_cents + pl.total_cut_cents, :>=, pl.monthly_target_cents, pl.template
      # cuts fund exactly the part above capacity — no rounding drift (trap #3)
      assert_equal [pl.monthly_target_cents - r.capacity_base_cents, 0].max, pl.total_cut_cents, pl.template
    end
  end

  test "recomendado holds the date when 25% trims cover the gap; cuts sum exactly to the gap" do
    # gap = required(352_942) − capacity(340_000) = 12_942; 25% of Restaurantes(200_000)=50_000 covers it.
    r = build(profile(capacity: 340_000, trimmables: { "Restaurantes" => 200_000 }))
    rec = r.plans.find { |p| p.template == "recomendado" }
    assert_equal r.required_monthly_cents, rec.monthly_target_cents
    assert_equal r.required_monthly_cents - r.capacity_base_cents, rec.total_cut_cents   # exact fill
    assert_equal Date.new(2027, 12, 1), rec.projected_done_on                            # holds D
  end

  test "leve trims lighter (15% off top-3) and its date may slip" do
    r = build(profile(capacity: 300_000, trimmables: { "Restaurantes" => 90_000, "Lazer" => 60_000, "Viagem" => 40_000, "Outros" => 30_000 }))
    leve = r.plans.find { |p| p.template == "leve" }
    assert_operator leve.cuts.size, :<=, Goals::LEVE_TOP_N
    assert_operator leve.monthly_target_cents, :<=, r.required_monthly_cents
  end

  test "tiny 1¢ gap is funded exactly with no drift" do
    # capacity one centavo under required → the single cut is exactly 1¢
    r = build(profile(capacity: Goals.ceil_div(6_000_000, 17) - 1, trimmables: { "Restaurantes" => 100_000 }))
    rec = r.plans.find { |p| p.template == "recomendado" }
    assert_equal 1, rec.total_cut_cents
    assert_equal r.required_monthly_cents, rec.monthly_target_cents
  end

  test "infeasible goal returns three exact counter-offers and zero plans" do
    # capacity 110_000, no trimmables, target 2.5M by out/2026 (4 months) → required 625_000 ≫ achievable
    r = Goals::PlanBuilder.call(profile: profile(capacity: 110_000), kind: "purchase",
                                target_cents: 2_500_000, starts_on: Date.new(2026, 7, 1),
                                target_date: Date.new(2026, 11, 1))
    refute r.feasible?
    assert_empty r.plans
    co = r.counter_offers
    assert_equal Goals.ceil_div(2_500_000, 4), co.required_monthly_cents            # 625_000
    assert_equal 110_000, co.achievable_monthly_cents                               # capacity, no trims
    assert_equal 625_000 - 110_000, co.extra_income_cents                           # honest income gap
    assert_equal 110_000 * 4, co.feasible_target_cents                              # reachable by the date
    assert_equal Date.new(2026, 7, 1) >> Goals.ceil_div(2_500_000, 110_000), co.feasible_date
  end

  test "savings_rate required is baseline guardado plus the extra; capacity funds it without cuts" do
    r = Goals::PlanBuilder.call(profile: profile(capacity: 320_000, guardado: 100_000),
                                kind: "savings_rate", target_cents: 50_000, starts_on: Date.new(2026, 7, 1))
    assert r.feasible?
    assert_equal 150_000, r.required_monthly_cents                # 100_000 baseline + 50_000 extra
    assert_equal [150_000, 150_000], r.plans.first(2).map(&:monthly_target_cents)
    assert r.plans.all? { |p| p.projected_done_on.nil? }         # open-ended
  end

  test "choose-time recompute from the frozen baseline is byte-identical" do
    p = profile(capacity: 320_000, trimmables: { "Restaurantes" => 62_000, "Lazer" => 40_000 })
    first  = build(p)
    reload = Goals::Profile.from_snapshot(JSON.parse(p.to_snapshot.to_json))
    second = build(reload)
    assert_equal first.plans.map(&:to_h), second.plans.map(&:to_h)
  end

  test "capacity contention subtracts other active goals' monthly targets (07 §1.3)" do
    p = profile(capacity: 150_000)
    r = Goals::PlanBuilder.call(profile: p, kind: "savings_rate", target_cents: 40_000,
                                starts_on: Date.new(2026, 7, 1), committed_elsewhere_cents: 100_000)
    assert_equal 50_000, r.capacity_base_cents   # 150_000 − 100_000 already committed
  end

  test "negative disposable income is NOT masked as R$0 — the goal is honestly infeasible (review HIGH)" do
    r = build(profile(capacity: -50_000, trimmables: { "Restaurantes" => 50_000 }))
    refute r.feasible?
    assert_equal(-50_000, r.capacity_base_cents)          # not clamped to 0
    co = r.counter_offers
    assert_equal r.required_monthly_cents - co.achievable_monthly_cents, co.extra_income_cents
    assert_nil co.feasible_date                           # can't save at negative capacity
    assert_equal 0, co.feasible_target_cents              # reachable target is just the head start
  end

  test "over-commitment pushes disposable negative via contention, routing to counter-offers" do
    p = profile(capacity: 150_000)
    r = Goals::PlanBuilder.call(profile: p, kind: "savings_rate", target_cents: 40_000,
                                starts_on: Date.new(2026, 7, 1), committed_elsewhere_cents: 200_000)
    assert_equal(-50_000, r.capacity_base_cents)          # 150_000 − 200_000, unclamped
    refute r.feasible?
  end
end
