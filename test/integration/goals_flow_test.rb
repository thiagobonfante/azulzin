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
    # required = ceil((6_000_000 - 0) / 16 months Aug'26→Dec'27 — plans anchor NEXT month, round 3),
    # hand-verified — shown as whole reais (ceil, round 3 P1)
    assert_match Goals.ceil_div(6_000_000, 16).then { |c| brl_whole_pt(c) }, @response.body

    assert_no_difference -> { @account.goals.count } do
      patch choose_goal_path(goal), params: { template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id }
    end
    assert_redirected_to goal_path(goal)
    assert goal.reload.active?
    assert_equal Date.new(2026, 8, 1), goal.starts_on
    assert goal.savings_commitment, "activation should create the savings commitment"
    assert_equal Date.new(2026, 8, 1), goal.savings_commitment.starts_on   # first occurrence next month

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

  test "activation without a caixinha/source is blocked with the friendly error (round 3)" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00", target_date: "2027-12-01" } }
    goal = @account.goals.last
    get goal_path(goal)   # populate baseline
    patch choose_goal_path(goal), params: { template: "recomendado" }
    assert_redirected_to goal_path(goal)
    assert_equal I18n.t("goals.choose.errors.missing_caixinha"), flash[:alert]
    assert goal.reload.draft?
    assert_nil goal.savings_commitment
  end

  test "activating writes the budget cuts at starts_on via the daily sweep; current month untouched" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00",
                                       target_date: "2027-12-01", initial_saved_reais: "0,00" } }
    goal = @account.goals.last
    follow_redirect!
    patch caps_goal_path(goal), params: { caps: { @rest.id.to_s => "15000" } }   # orçamento slider → fixed cut
    @rest.update!(monthly_budget_cents: 60_000)                                  # standing budget above the cap
    patch choose_goal_path(goal), params: { template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id }
    assert goal.reload.active?

    Goals::ApplyBudgetCutsJob.perform_now                     # July sweep: goal starts August → no-op
    assert_equal 60_000, @rest.reload.monthly_budget_cents
    assert_nil goal.reload.budgets_applied_at

    travel_to Time.utc(2026, 8, 2, 12)
    Goals::ApplyBudgetCutsJob.perform_now                     # August sweep: cap written into the orçamento
    assert_equal 15_000, @rest.reload.monthly_budget_cents
    assert_not_nil goal.reload.budgets_applied_at

    get categories_path
    assert_response :success
    assert_match "150,00", @response.body                     # the categories screen shows the cut value (R$ 150,00)

    patch abandon_goal_path(goal)
    assert_equal 60_000, @rest.reload.monthly_budget_cents    # reverted on abandon
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

  # ── Round 3 P1 regressions: submit what a real BROWSER submits ─────────────────────────
  # The include_blank:false date select is always pre-filled, and a blank "já guardado"
  # arrives as "" — both must not block a savings_rate (or purchase) creation.

  test "savings_rate create succeeds even with the browser-submitted date + blank já guardado" do
    assert_difference -> { @account.goals.count }, 1 do
      post goals_path, params: { goal: { name: "Guardar mais", kind: "savings_rate", target_reais: "800",
                                         target_date: Date.new(2026, 8, 1).iso8601, initial_saved_reais: "" } }
    end
    goal = @account.goals.last
    assert_redirected_to goal_path(goal)
    assert goal.savings_rate?
    assert_nil goal.target_date
    assert_equal 0, goal.initial_saved_cents
    assert_equal 80_000, goal.target_cents
  end

  test "purchase create with a blank já guardado keeps the default 0 and succeeds" do
    assert_difference -> { @account.goals.count }, 1 do
      post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000",
                                         target_date: "2027-12-01", initial_saved_reais: "" } }
    end
    goal = @account.goals.last
    assert_redirected_to goal_path(goal)
    assert_equal 0, goal.initial_saved_cents
    assert_equal 6_000_000, goal.target_cents, "masked whole-real input (60.000) parses as whole reais"
  end

  test "a 422 re-render prefills the money inputs with whole-real strings (mask-safe)" do
    assert_no_difference -> { @account.goals.count } do
      post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000",
                                         target_date: "2027-12-01", initial_saved_reais: "70.000" } }
    end
    assert_response :unprocessable_entity
    # NEVER the default _reais prefill ("60000,00") — a digits-only mask would read it ×100.
    assert_select "input[name='goal[target_reais]'][value='60.000']"
    assert_select "input[name='goal[initial_saved_reais]'][value='70.000']"
  end

  # ── Round 3 P3: initial-saved earmarking, parcel status, speed-up ──────────────────────

  test "create with 'já tenho um valor guardado' persists the amount and its caixinha" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000",
                                       target_date: "2027-12-01", initial_saved_reais: "5.000",
                                       initial_saved_bank_account_id: @caixinha.id } }
    goal = @account.goals.last
    assert_redirected_to goal_path(goal)
    assert_equal 500_000, goal.initial_saved_cents
    assert_equal @caixinha.id, goal.initial_saved_bank_account_id
  end

  test "an initial amount without its caixinha is refused while one exists to point at" do
    assert_no_difference -> { @account.goals.count } do
      post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000",
                                         target_date: "2027-12-01", initial_saved_reais: "5.000" } }
    end
    assert_response :unprocessable_entity
  end

  test "the gap month shows the commitment but no dead Pagar button (parcel starts next month)" do
    goal = activate_goal!
    get goal_path(goal)
    assert_response :success
    refute_match "commitment_occurrences", @response.body   # the pay form's path never renders
  end

  test "paying this month's parcel from the goal page lands back on the goal" do
    goal = activate_goal!
    travel_to Time.utc(2026, 8, 10, 12)
    get goal_path(goal)
    assert_match "commitment_occurrences/#{goal.savings_commitment.id}-2026-08/pay", @response.body

    patch pay_commitment_occurrence_path("#{goal.savings_commitment.id}-2026-08", from: "goal")
    assert_redirected_to goal_path(goal)
    assert goal.savings_commitment.paid_in?(Date.new(2026, 8, 1))
    follow_redirect!
    assert_response :success
    assert_select "form[action*='commitment_occurrences']", count: 0   # paid → quiet line, no button
  end

  test "speed-up: paid parcel + spare sobra shows the card and contribute posts a bounded transfer" do
    goal = activate_goal!
    august!(goal)

    get goal_path(goal)
    assert_match I18n.t("goals.show.speed_up_title"), @response.body

    before = Goals::Progress.new(goal).actual_cents
    assert_difference -> { @account.transactions.where(direction: "transfer").count }, 1 do
      post contribute_goal_path(goal), params: { amount_reais: "100" }
    end
    assert_redirected_to goal_path(goal)
    txn = @account.transactions.where(direction: "transfer").order(:id).last
    assert_equal 10_000, txn.amount_cents
    assert_nil txn.commitment_id, "a speed-up transfer must never look like a second parcel payment"
    assert_equal @caixinha.id, txn.transfer_to_bank_account_id
    assert_equal @checking.id, txn.bank_account_id
    assert_equal before + 10_000, Goals::Progress.new(goal).actual_cents
  end

  test "a contribute above the sobra is rejected with no transfer" do
    goal = activate_goal!
    august!(goal)
    assert_no_difference -> { @account.transactions.where(direction: "transfer").count } do
      post contribute_goal_path(goal), params: { amount_reais: "999.999" }
    end
    assert_redirected_to goal_path(goal)
    assert_equal I18n.t("goals.contribute.rejected"), flash[:alert]
  end

  test "contribute on a draft goal is rejected" do
    post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000",
                                       target_date: "2027-12-01" } }
    goal = @account.goals.last
    assert_no_difference -> { @account.transactions.count } do
      post contribute_goal_path(goal), params: { amount_reais: "100" }
    end
    assert_equal I18n.t("goals.contribute.rejected"), flash[:alert]
  end

  private
    def activate_goal!
      post goals_path, params: { goal: { name: "Carro", kind: "purchase", target_reais: "60.000,00",
                                         target_date: "2027-12-01", initial_saved_reais: "0,00" } }
      goal = @account.goals.last
      get goal_path(goal)   # populate baseline
      patch choose_goal_path(goal), params: { template: "recomendado", bank_account_id: @caixinha.id,
                                              source_bank_account_id: @checking.id }
      goal.reload
    end

    # First scheduled month (starts_on = August): income lands and the parcel gets paid.
    def august!(goal)
      travel_to Time.utc(2026, 8, 10, 12)
      month = Date.new(2026, 8, 1)
      @account.transactions.create!(direction: "income", status: "posted", amount_cents: 900_000,
                                    bank_account: @checking, occurred_on: month,
                                    billing_month: month, billing_month_manual: true)
      Commitments::MarkPaid.call(goal.savings_commitment, month)
    end

    # brl_whole in the pt-BR pinned UI (round 3 P1 — goals shows whole reais, ceil): "R$ 3.530"
    def brl_whole_pt(cents) = I18n.with_locale(:"pt-BR") { ActionController::Base.helpers.number_to_currency(BigDecimal(Money.ceil_to_real(cents)) / 100, unit: "R$", precision: 0) }
end
