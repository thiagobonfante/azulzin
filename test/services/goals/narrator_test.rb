require "test_helper"

# Touchpoint 1 (.plans/goals 04 §1): one call phrases all 3 notes; the digit-mismatch guard and
# every failure path fall back to template notes. Injectable client — no network.
class Goals::NarratorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(parsed) = (@parsed = parsed; @calls = 0)
    def chat(**_) = (@calls += 1; OpenRouterClient::Result.new(parsed: @parsed))
  end

  setup { @account = users(:confirmed).account }

  def draft(capacity: 400_000)
    profile = Goals::Profile.new(sufficiency: :ok, categories: [], median_income_cents: 900_000,
                                 median_capacity_base_cents: capacity, median_guardado_cents: 0,
                                 income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
                                 window: [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ])
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000, target_date: Date.new(2027, 12, 1),
                           status: "draft", starts_on: Date.new(2026, 7, 1), baseline: profile.to_snapshot)
  end

  def parsed_notes(text) = { "plans" => %w[leve recomendado acelerado].map { |k| { "key" => k, "narrative" => text } } }

  test "phrases all three plans in exactly one call" do
    client = FakeClient.new(parsed_notes("Um caminho tranquilo, sem apertar."))
    result = Goals::Narrator.call(draft, client: client)
    assert_equal 1, client.calls
    assert_equal %w[leve recomendado acelerado], result.keys - [ "fp" ]
    assert result["fp"].present?, "narratives carry a plan fingerprint for staleness invalidation"
    assert_equal "Um caminho tranquilo, sem apertar.", result["recomendado"]

    # the fingerprint matches the plans it was built from (so the card renders it)
    assert_equal Goals.plan_fingerprint(Goals::Recompute.call(draft)), result["fp"]
  end

  test "digit-mismatch guard rejects an invented money figure → nil (template notes stand)" do
    client = FakeClient.new(parsed_notes("Guarde R$ 999.999,99 por mês e chega antes."))
    assert_nil Goals::Narrator.call(draft, client: client)
  end

  test "digit guard also rejects an invented bare number (a wrong year/count)" do
    client = FakeClient.new(parsed_notes("Você termina em 2050, bem tranquilo."))
    assert_nil Goals::Narrator.call(draft, client: client)
  end

  test "a client error falls back to nil" do
    raising = Object.new
    def raising.chat(**_) = raise(OpenRouterClient::RateLimited, "rate limited")
    assert_nil Goals::Narrator.call(draft, client: raising)
  end

  test "an infeasible goal is never narrated (zero calls)" do
    g = draft(capacity: -100_000)
    client = FakeClient.new({})
    assert_nil Goals::Narrator.call(g, client: client)
    assert_equal 0, client.calls
  end
end
