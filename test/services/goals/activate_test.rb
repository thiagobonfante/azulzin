require "test_helper"

# Guarded activation + "pay yourself first" savings-commitment creation, and the MarkPaid transfer
# fork (.plans/goals 01 §5, 07 §1.2). Money moves only when the user pays the occurrence.
class Goals::ActivateTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings")
    travel_to Time.utc(2026, 7, 15, 12)
  end

  teardown { travel_back }

  # A draft goal whose frozen baseline makes a R$6.000.000 purchase feasible.
  def draft(**attrs)
    profile = Goals::Profile.new(
      sufficiency: :ok,
      categories: [ Goals::CategoryStat.new(category_id: 1, name: "Restaurantes", median_cents: 200_000,
                                           trimmable_median_cents: 200_000, months_present: 3, flexibility: "flexible") ],
      median_income_cents: 900_000, median_capacity_base_cents: 400_000, median_guardado_cents: 0,
      income_irregular: false, uncategorized_ratio_bd: BigDecimal(0),
      window: [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ]
    )
    @account.goals.create!({ name: "Carro", kind: "purchase", target_cents: 6_000_000,
                             target_date: Date.new(2027, 12, 1), status: "draft",
                             baseline: profile.to_snapshot }.merge(attrs))
  end

  test "activating a feasible draft flips it active and creates the savings commitment" do
    g = draft
    result = Goals::Activate.call(g, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    assert result.ok?
    g.reload
    assert g.active?
    assert_equal Date.new(2026, 7, 1), g.starts_on
    assert_operator g.monthly_target_cents, :>, 0
    assert_equal @caixinha.id, g.bank_account_id
    assert_equal "recomendado", g.plan["template"]

    c = g.savings_commitment
    assert c, "expected a savings commitment"
    assert_equal "savings", c.kind
    assert_equal @checking.id, c.bank_account_id            # source
    assert_equal g.monthly_target_cents, c.amount_cents
    assert_equal Date.new(2027, 12, 1).beginning_of_month, c.ends_on
  end

  test "the chosen plan is recomputed from the frozen baseline, not trusted from params" do
    g = draft
    expected = Goals::Recompute.call(g).plans.find { |p| p.template == "recomendado" }
    Goals::Activate.call(g, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    assert_equal expected.monthly_target_cents, g.reload.monthly_target_cents
    assert_equal expected.to_snapshot, g.plan
  end

  test "double activation is a no-op — one commitment, second call reports not_draft" do
    g = draft
    first  = Goals::Activate.call(g, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    second = Goals::Activate.call(g, template: "acelerado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    assert first.ok?
    refute second.ok?
    assert_equal :not_draft, second.error
    assert_equal 1, g.commitments.savings.count
  end

  test "activation refuses over the 5-active cap" do
    5.times { @account.goals.create!(name: "x", kind: "savings_rate", target_cents: 1_000, status: "active") }
    result = Goals::Activate.call(draft, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    refute result.ok?
    assert_equal :too_many_active, result.error
  end

  test "an unknown template is refused" do
    result = Goals::Activate.call(draft, template: "turbo", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    assert_equal :invalid_template, result.error
  end

  test "an infeasible draft cannot be activated" do
    poor = draft
    poor.update!(baseline: poor.baseline.merge("median_capacity_base_cents" => -100_000))
    result = Goals::Activate.call(poor, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    assert_equal :infeasible, result.error
  end

  test "rejects a non-savings or cross-account caixinha (update_all can't validate)" do
    checking = @account.bank_accounts.create!(institution: @inst, kind: "checking")
    assert_equal :not_savings, Goals::Activate.call(draft, template: "recomendado", bank_account_id: checking.id, source_bank_account_id: @checking.id).error

    stray = Account.create!(name: "B").bank_accounts.create!(institution: @inst, kind: "savings")
    assert_equal :not_savings, Goals::Activate.call(draft, template: "recomendado", bank_account_id: stray.id, source_bank_account_id: @checking.id).error
  end

  test "rejects a cross-account funding source" do
    stray = Account.create!(name: "B").bank_accounts.create!(institution: @inst, kind: "checking")
    result = Goals::Activate.call(draft, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: stray.id)
    assert_equal :invalid_source, result.error
  end

  test "a commitment cannot be created with an instrument from another account (model backstop)" do
    stray = Account.create!(name: "B").bank_accounts.create!(institution: @inst, kind: "checking")
    goal = @account.goals.create!(name: "G", kind: "savings_rate", target_cents: 10_000, status: "active")
    c = @account.commitments.new(kind: "savings", goal:, bank_account: stray, amount_cents: 1_000,
                                 name: "x", starts_on: Date.new(2026, 7, 1), schedule_day: 5)
    refute c.valid?
  end

  test "an unlinked goal activates without a commitment (all-savings fallback)" do
    g = draft
    result = Goals::Activate.call(g, template: "recomendado", bank_account_id: nil, source_bank_account_id: nil)
    assert result.ok?
    assert g.reload.active?
    assert_nil g.savings_commitment
  end

  test "paying the savings commitment posts a transfer into the caixinha and counts as guardado" do
    g = draft
    Goals::Activate.call(g, template: "recomendado", bank_account_id: @caixinha.id, source_bank_account_id: @checking.id)
    c = g.savings_commitment

    txn = Commitments::MarkPaid.call(c, Date.new(2026, 7, 1))

    assert_equal "transfer", txn.direction
    assert_equal @caixinha.id, txn.transfer_to_bank_account_id
    assert_equal @checking.id, txn.bank_account_id
    assert_nil txn.category_id
    assert c.paid_in?(Date.new(2026, 7, 1))
    assert_equal txn.amount_cents, MonthSummary.new(@account, Date.new(2026, 7, 1)).guardado_cents
    assert_equal g.initial_saved_cents + txn.amount_cents, Goals::Progress.new(g).actual_cents
  end
end
