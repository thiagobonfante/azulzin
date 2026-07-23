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
                       median_capacity_base_cents: capacity, median_saved_cents: guardado,
                       income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
                       window: [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ])
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
      assert_equal [ pl.monthly_target_cents - r.capacity_base_cents, 0 ].max, pl.total_cut_cents, pl.template
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

  test "savings_rate required IS the desired monthly total; leve eases only the extra" do
    r = Goals::PlanBuilder.call(profile: profile(capacity: 320_000, guardado: 100_000),
                                kind: "savings_rate", target_cents: 150_000, starts_on: Date.new(2026, 7, 1))
    assert r.feasible?
    assert_equal 150_000, r.required_monthly_cents                # the total asked, not guardado + extra
    leve, rec = r.plans.first(2)
    assert_equal 100_000 + Goals.pct_of(50_000, Goals::LEVE_EASE), leve.monthly_target_cents  # never below today's pace
    assert_equal 150_000, rec.monthly_target_cents
    assert r.plans.all? { |p| p.projected_done_on.nil? }         # open-ended
  end

  test "savings_rate counter-offer is the achievable monthly TOTAL" do
    r = Goals::PlanBuilder.call(profile: profile(capacity: 100_000, guardado: 80_000),
                                kind: "savings_rate", target_cents: 300_000, starts_on: Date.new(2026, 7, 1))
    refute r.feasible?
    assert_equal 100_000, r.counter_offers.feasible_target_cents   # capacity, no trims
  end

  test "leve eases to 85% of required even when the sobra covers everything — never a recomendado clone" do
    r = build(profile(capacity: 500_000, trimmables: { "Restaurantes" => 90_000 }))
    leve = r.plans.find { |p| p.template == "leve" }
    rec  = r.plans.find { |p| p.template == "recomendado" }
    assert_equal Goals.pct_of(r.required_monthly_cents, Goals::LEVE_EASE), leve.monthly_target_cents
    assert_equal r.required_monthly_cents, rec.monthly_target_cents
    assert_operator leve.projected_done_on, :>, rec.projected_done_on   # the date honestly slips
    assert_empty leve.cuts
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

  # ---- user caps (orçamento sliders) --------------------------------------------------------

  test "a user cap is a fixed cut carried by EVERY plan and off the table for template trims" do
    p = profile(capacity: 300_000, trimmables: { "Restaurantes" => 90_000, "Lazer" => 60_000 })
    r = build(p, user_caps: { 1 => 50_000 })              # Restaurantes capped 90_000 → 50_000
    assert r.feasible?
    r.plans.each do |pl|
      resto = pl.cuts.find { |c| c.category_id == 1 }
      assert_equal 40_000, resto.cut_cents, pl.template   # the exact user cut, template-independent
      assert_equal 50_000, resto.cap_cents, pl.template
      assert_equal 1, pl.cuts.count { |c| c.category_id == 1 }, pl.template   # never trimmed twice
    end
  end

  test "user caps accelerate every plan and keep the cents-exact invariant (hand-verified)" do
    # required 352_942 · capacity 340_000 · user cut 40_000 (Restaurantes 90_000 → 50_000)
    p = profile(capacity: 340_000, trimmables: { "Restaurantes" => 90_000, "Lazer" => 60_000 })
    r = build(p, user_caps: { 1 => 50_000 })
    leve, rec, acel = r.plans
    assert_equal Goals.pct_of(352_942, Goals::LEVE_EASE) + 40_000, leve.monthly_target_cents  # eased + cap money
    assert_equal 380_000, rec.monthly_target_cents            # capacity covers required; cap surplus accelerates
    assert_equal 404_000, acel.monthly_target_cents           # stretch capped at capacity + cap + 40% of Lazer
    r.plans.each do |pl|
      # generalized invariant: monthly == min(template need, capacity) + Σcuts — cents exact
      assert_equal pl.monthly_target_cents - pl.total_cut_cents,
                   [ pl.monthly_target_cents - pl.total_cut_cents, r.capacity_base_cents ].min, pl.template
      assert_equal 40_000, pl.cuts.find { |c| c.category_id == 1 }.cut_cents, pl.template
    end
  end

  test "a user cap can flip an infeasible goal to feasible (caps go beyond the 40% template max)" do
    # required 625_000; capacity 500_000 + 40% of 200_000 = 580_000 → infeasible without the cap
    without = Goals::PlanBuilder.call(profile: profile(capacity: 500_000, trimmables: { "Restaurantes" => 200_000 }),
                                      kind: "purchase", target_cents: 2_500_000,
                                      starts_on: Date.new(2026, 7, 1), target_date: Date.new(2026, 11, 1))
    refute without.feasible?
    with = Goals::PlanBuilder.call(profile: profile(capacity: 500_000, trimmables: { "Restaurantes" => 200_000 }),
                                   kind: "purchase", target_cents: 2_500_000,
                                   starts_on: Date.new(2026, 7, 1), target_date: Date.new(2026, 11, 1),
                                   user_caps: { 1 => 60_000 })   # cut 140_000 — the user's own call
    assert with.feasible?
  end

  test "user cap cut is clamped to the trimmable slice and a no-op cap is dropped" do
    cats = [ Goals::CategoryStat.new(category_id: 1, name: "Mercado", median_cents: 100_000,
                                     trimmable_median_cents: 30_000, months_present: 3, flexibility: "flexible") ]
    p = Goals::Profile.new(sufficiency: :ok, categories: cats, median_income_cents: 920_000,
                           median_capacity_base_cents: 340_000, median_saved_cents: 0,
                           income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
                           window: [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ])
    r = build(p, user_caps: { 1 => 10_000 })              # asks to cut 90_000 — only 30_000 is trimmable
    cut = r.plans.first.cuts.find { |c| c.category_id == 1 }
    assert_equal 30_000, cut.cut_cents                    # clamped to the commitment-less slice
    noop = build(p, user_caps: { 1 => 100_000 })          # cap == median → nothing to cut
    assert(noop.plans.all? { |pl| pl.cuts.none? { |c| c.category_id == 1 } })
  end
end
