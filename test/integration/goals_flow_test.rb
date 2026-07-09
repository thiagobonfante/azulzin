require "test_helper"

# End-to-end creation slice (.plans/goals Phase 1): create → diagnóstico + 3 plans → choose →
# active goal on the dashboard. Also the infeasible counter-offer state and the 5-active cap.
class GoalsFlowTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  WINDOW = [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ].freeze

  setup do
    @user = users(:confirmed)
    @user.update!(onboarded_at: Time.current)
    @account = @user.account
    @inst = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    @rest = @account.categories.create!(name: "Restaurantes")
    travel_to Time.utc(2026, 7, 15, 12)
    seed_ledger
    sign_in_as @user
  end

  teardown { travel_back }

  def seed_ledger
    WINDOW.each do |m|
      @account.transactions.create!(direction: "income", status: "posted", amount_cents: 900_000,
                                    bank_account: @checking, occurred_on: m, billing_month: m, billing_month_manual: true)
      10.times do
        @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 20_000,
                                      category: @rest, bank_account: @checking, occurred_on: m,
                                      billing_month: m, billing_month_manual: true)
      end
    end
  end

  test "create a purchase goal, see 3 plans, choose one, and it goes active on the dashboard" do
    get new_goal_path
    assert_response :success

    assert_difference -> { @account.goals.count }, 1 do
      post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00",
                                         target_date: "2027-12-01", initial_saved_reais: "0,00" } }
    end
    goal = @account.goals.last
    assert_redirected_to goal_path(goal)
    assert goal.draft?

    follow_redirect!   # draft screen
    assert_response :success
    assert_select "label", text: /Recomendado/
    # required = ceil((6_000_000 - 0) / 17), hand-verified
    assert_match Goals.ceil_div(6_000_000, 17).then { |c| brl_pt(c) }, @response.body

    assert_no_difference -> { @account.goals.count } do
      patch choose_goal_path(goal), params: { template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id }
    end
    assert_redirected_to goal_path(goal)
    assert goal.reload.active?
    assert goal.savings_commitment, "activation should create the savings commitment"

    get dashboard_path
    assert_response :success
    assert_match "Carro", @response.body
  end

  test "creating a draft enqueues the coach narrative + the category classifier" do
    assert_enqueued_with(job: Goals::NarrativeJob) do
      assert_enqueued_with(job: Goals::ClassifyJob) do
        post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
      end
    end
  end

  test "the 6th goal draft this month does not enqueue a narrative (AI session quota)" do
    5.times { |i| @account.goals.create!(name: "d#{i}", kind: "savings_rate", target_cents: 1_000, status: "draft") }
    assert_no_enqueued_jobs only: Goals::NarrativeJob do
      post goals_path, params: { goal: { name: "Sexto", kind: "savings_rate", target_reais: "100,00" } }
    end
  end

  test "a stale cached narrative (fingerprint mismatch) falls back to the template note" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
    goal = @account.goals.last
    goal.update!(baseline: goal.baseline.merge("narratives" => { "fp" => "stale", "recomendado" => "Texto antigo inválido." }))
    get goal_path(goal)
    assert_response :success
    refute_match "Texto antigo inválido.", @response.body
  end

  test "an infeasible goal shows counter-offers, not plan cards" do
    post goals_path, params: { goal: { name: "Moto", kind: "purchase", target_reais: "250.000,00",
                                       target_date: "2026-11-01", initial_saved_reais: "0,00" } }
    follow_redirect!
    assert_response :success
    assert_match I18n.t("goals.states.too_tight_title"), @response.body
    assert_select "label", text: /Recomendado/, count: 0
  end

  test "the 6th active goal is blocked — new redirects to the index" do
    5.times { @account.goals.create!(name: "g", kind: "savings_rate", target_cents: 1_000, status: "active") }
    get new_goal_path
    assert_redirected_to goals_path
  end

  test "create analyzes the baseline in-request — the narrative job can never race an empty snapshot" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
    assert_equal "ok", @account.goals.last.baseline["sufficiency"]
  end

  test "a savings goal at or below today's guardado is refused with a clear error" do
    WINDOW.each do |m|
      @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 150_000,
                                    bank_account: @checking, transfer_to_bank_account: @caixinha,
                                    occurred_on: m, billing_month: m, billing_month_manual: true)
    end
    assert_no_difference -> { @account.goals.count } do
      post goals_path, params: { goal: { name: "Guardar", kind: "savings_rate", target_reais: "1.000,00" } }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.attributes.goal.target_cents"), @response.body
  end

  test "dragging an orçamento slider stores the cap and recomputes the plans with the fixed cut" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
    goal = @account.goals.last
    follow_redirect!
    assert_select "input[type=range][name=?]", "caps[#{@rest.id}]"

    patch caps_goal_path(goal), params: { caps: { @rest.id.to_s => "15000", "999999" => "100" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "goal_plan_area", @response.body
    assert_equal({ @rest.id.to_s => 15_000 }, goal.reload.user_caps)   # junk category id dropped

    build = Goals::Recompute.call(goal)
    assert build.plans.all? { |p| p.cuts.any? { |c| c.category_id == @rest.id && c.cap_cents == 15_000 } }

    patch caps_goal_path(goal), params: { reset: "1" }
    assert_empty goal.reload.user_caps
  end

  test "double-submitting choose activates only once" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
    goal = @account.goals.last
    get goal_path(goal)   # populate baseline
    patch choose_goal_path(goal), params: { template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id }
    patch choose_goal_path(goal), params: { template: "acelerado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id }
    assert_equal 1, goal.commitments.savings.count
    assert_equal "recomendado", goal.reload.plan["template"]
  end

  private
    # brl in the pt-BR pinned UI: "R$ 3.529,42"
    def brl_pt(cents) = I18n.with_locale(:"pt-BR") { ActionController::Base.helpers.number_to_currency(BigDecimal(cents) / 100, unit: "R$") }
end
