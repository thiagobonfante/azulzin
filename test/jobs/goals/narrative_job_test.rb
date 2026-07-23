require "test_helper"

# AI cost controls (.plans/goals 07 §2) + the load-bearing regression gate: ZERO LLM on the
# weekly check/notify path.
class Goals::NarrativeJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
  end

  teardown { travel_back }

  def draft
    profile = Goals::Profile.new(sufficiency: :ok, categories: [], median_income_cents: 900_000,
                                 median_capacity_base_cents: 400_000, median_saved_cents: 0,
                                 income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
                                 window: [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ])
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000, target_date: Date.new(2027, 12, 1),
                           status: "draft", starts_on: Date.new(2026, 7, 1), baseline: profile.to_snapshot)
  end

  test "increments ai_calls_count and refuses past the per-session cap of 3" do
    goal = draft
    calls = 0
    Goals::Narrator.stub(:call, ->(*) { calls += 1; nil }) do
      4.times { Goals::NarrativeJob.perform_now(goal.id) }
    end
    assert_equal 3, calls                          # the 4th is refused with no call
    assert_equal 3, goal.reload.ai_calls_count
  end

  test "a not-yet-analyzed draft is skipped BEFORE burning quota (create-time race regression)" do
    goal = @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000,
                                  target_date: Date.new(2027, 12, 1), status: "draft")
    called = false
    Goals::Narrator.stub(:call, ->(*) { called = true; nil }) do
      Goals::NarrativeJob.perform_now(goal.id)
    end
    refute called, "Narrator must not run against an empty baseline"
    assert_equal 0, goal.reload.ai_calls_count
  end

  test "caches the returned narratives onto the baseline" do
    goal = draft
    notes = { "leve" => "a", "recomendado" => "b", "acelerado" => "c" }
    Goals::Narrator.stub(:call, ->(*) { notes }) do
      Goals::NarrativeJob.perform_now(goal.id)
    end
    assert_equal notes, goal.reload.baseline["narratives"]
  end

  test "ZERO LLM calls on the entire weekly check + notify path (regression gate)" do
    @account.goals.create!(name: "Carro", kind: "purchase", target_cents: 6_000_000, target_date: Date.new(2027, 12, 1),
                           status: "active", monthly_target_cents: 300_000, starts_on: Date.new(2026, 7, 1),
                           activated_at: Time.utc(2026, 7, 1), bank_account: @caixinha,
                           baseline: { "median_income_cents" => 0, "categories" => [] })
    travel_to Time.utc(2026, 7, 31, 12)
    OpenRouterClient.stub(:new, ->(*) { raise "the LLM must never be constructed on the check path" }) do
      Goals::NotifyMemberJob.perform_now(@account.id, users(:confirmed).id, Date.new(2026, 7, 31))
    end
    assert GoalCheck.exists?, "the check still ran — just without any LLM"
  end
end
