require "test_helper"

# The canonical worked example (.plans/credit-cards 02 §6), verbatim to the centavo, plus
# the property tests. Rates frozen at the May/2026 SGS aggregates: rotativo 15,09% a.m.,
# parcelamento 9,26% a.m. — tests NEVER call the BCB API.
class RotativoTest < ActiveSupport::TestCase
  ROT  = BigDecimal("15.09")
  PARC = BigDecimal("9.26")

  # R$ 3.000,00 bill, pays 15% (R$ 450,00) → financed 255.000¢.
  test "canonical table: cycle cost" do
    cost = Rotativo.cycle_cost(255_000, monthly_rate: ROT)
    assert_equal 38_480, cost[:juros_cents]
    assert_equal 969 + 627, cost[:iof_cents]     # 0,38% fixed + 0,0082%/day × 30
    assert_equal 40_076, cost[:total_cents]      # next fatura gains exactly this
  end

  test "canonical table: full projection to the centavo" do
    p = Rotativo.projection(300_000, 45_000, rotativo_am: ROT, parcelado_am: PARC)

    assert_equal 255_000, p[:financed_cents]
    assert_equal 40_076,  p[:next_bill_add_cents]
    assert_equal 295_076, p[:financed_cents] + p[:next_bill_add_cents]   # next fatura
    assert_equal 41_749,  p[:parcel_cents]                               # 12× parcela
    assert_equal 185_839, p[:schedule][5]                                # after 6 parcels
    assert_equal 0,       p[:schedule].last
    assert_equal 545_986, p[:total_cost_cents]                           # custo até quitar
    assert_equal 245_986, p[:encargos_cents]
    assert_equal 255_000, p[:cap_cents]                                  # Lei 14.690: 100%
    assert p[:encargos_cents] < p[:cap_cents]
    assert_equal 5, p[:months_to_cap]                                    # "dobra em ~5 meses"
  end

  test "parcel helper matches the projection's displayed installment" do
    assert_equal 41_749, Rotativo.parcel(295_076, monthly_rate: PARC)
  end

  test "no projection when nothing is financed (full payment or overpay)" do
    assert_nil Rotativo.projection(300_000, 300_000, rotativo_am: ROT, parcelado_am: PARC)
    assert_nil Rotativo.projection(300_000, 310_000, rotativo_am: ROT, parcelado_am: PARC)
  end

  # Property tests across a matrix of bills, payments and plausible rates.
  test "properties: schedule strictly decreasing, parcels-minus-financed equals encargos, cap never exceeded" do
    [ [ 300_000, 45_000 ], [ 125_000, 1 ], [ 1_000_000, 150_000 ], [ 8_35, 1_00 ], [ 54_321, 12_345 ] ].each do |bill, paid|
      [ [ ROT, PARC ], [ BigDecimal("20"), BigDecimal("12") ], [ BigDecimal("9"), BigDecimal("5") ] ].each do |rot, parc|
        p = Rotativo.projection(bill, paid, rotativo_am: rot, parcelado_am: parc)
        label = "bill=#{bill} paid=#{paid} rot=#{rot.to_f} parc=#{parc.to_f}"

        assert_equal p[:schedule], p[:schedule].sort.reverse, "schedule decreasing (#{label})"
        assert_equal p[:schedule].uniq, p[:schedule], "strictly (#{label})"
        assert_equal 0, p[:schedule].last, "Price zeroes the debt (#{label})"

        unless p[:encargos_cents] == p[:cap_cents]   # unclamped ⇒ the identity holds exactly
          parcels_total = p[:total_cost_cents] - paid
          assert_equal p[:encargos_cents], parcels_total - p[:financed_cents],
                       "Σ parcels − financed = encargos (#{label})"
        end
        assert p[:encargos_cents] <= p[:cap_cents], "encargos never exceed the 100% cap (#{label})"
        assert p[:months_to_cap].positive?, label
      end
    end
  end

  # The cap CLAMP engages under stress rates (regulated ceiling, .plans/credit-cards 02 §1).
  test "encargos clamp at 100% of the financed remainder under stress rates" do
    p = Rotativo.projection(100_000, 1_000, rotativo_am: BigDecimal("25"), parcelado_am: BigDecimal("20"))
    assert_equal p[:cap_cents], p[:encargos_cents]
    assert_equal 100_000 + p[:cap_cents], p[:total_cost_cents], "the debt at most doubles"
  end
end
