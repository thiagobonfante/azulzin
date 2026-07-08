require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @account = users(:confirmed).account
    @inst    = Institution.find_by(code: "260")
    @savings = @account.bank_accounts.create!(institution: @inst, kind: "savings", nickname: "Caixinha")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking", nickname: "Conta")
  end

  def purchase(**attrs)
    @account.goals.new({ name: "Carro", kind: "purchase", target_cents: 6_000_000,
                         target_date: Date.new(2027, 12, 1) }.merge(attrs))
  end

  test "a valid purchase draft saves" do
    assert purchase.valid?
  end

  test "purchase requires a target_date; savings_rate forbids one" do
    refute purchase(target_date: nil).valid?
    assert_includes purchase(target_date: nil).tap(&:valid?).errors.attribute_names, :target_date
    refute @account.goals.new(name: "X", kind: "savings_rate", target_cents: 50_000, target_date: Date.new(2027, 1, 1)).valid?
  end

  test "DB check constraint rejects a purchase without a date even when validations are bypassed" do
    g = purchase(target_date: nil)
    assert_raises(ActiveRecord::StatementInvalid) { g.save(validate: false) }
  end

  test "DB check constraint rejects target_cents <= 0" do
    g = @account.goals.new(name: "X", kind: "savings_rate", target_cents: 0)
    assert_raises(ActiveRecord::StatementInvalid) { g.save(validate: false) }
  end

  test "money_column parses pt-BR into cents" do
    g = purchase
    g.target_reais = "60.000,00"
    assert_equal 6_000_000, g.target_cents
  end

  test "a purchase target must exceed the initial saved amount (no already-achieved goals)" do
    refute purchase(initial_saved_cents: 6_000_000).valid?
    refute purchase(initial_saved_cents: 7_000_000).valid?
    assert purchase(initial_saved_cents: 5_999_999).valid?
  end

  test "DB check constraint rejects monthly_target_cents = 0" do
    g = @account.goals.new(name: "X", kind: "savings_rate", target_cents: 10_000, monthly_target_cents: 0)
    assert_raises(ActiveRecord::StatementInvalid) { g.save(validate: false) }
  end

  test "DB check constraint rejects a savings_rate goal carrying a target_date" do
    g = @account.goals.new(name: "X", kind: "savings_rate", target_cents: 10_000, target_date: Date.new(2027, 1, 1))
    assert_raises(ActiveRecord::StatementInvalid) { g.save(validate: false) }
  end

  test "DB check constraint rejects negative initial_saved_cents" do
    g = @account.goals.new(name: "X", kind: "savings_rate", target_cents: 10_000, initial_saved_cents: -1)
    assert_raises(ActiveRecord::StatementInvalid) { g.save(validate: false) }
  end

  test "a commitment's goal link is allowed only on the savings kind" do
    goal = @account.goals.create!(name: "G", kind: "savings_rate", target_cents: 10_000, status: "active")
    bad  = @account.commitments.new(kind: "fixed", bank_account: @checking, amount_cents: 1_000,
                                    name: "Aluguel", starts_on: Date.new(2026, 7, 1), schedule_day: 5, goal:)
    refute bad.valid?
    ok = @account.commitments.new(kind: "savings", bank_account: @checking, amount_cents: 1_000,
                                  name: "Meta", starts_on: Date.new(2026, 7, 1), schedule_day: 5, goal:)
    assert ok.valid?
  end

  test "linked bank_account must be a savings caixinha in the same account" do
    refute purchase(bank_account: @checking).valid?
    assert purchase(bank_account: @savings).valid?

    other = Account.create!(name: "Other")
    stray = other.bank_accounts.create!(institution: @inst, kind: "savings")
    refute purchase(bank_account: stray).valid?
  end

  test "at most 5 active goals per account" do
    5.times { |i| @account.goals.create!(name: "G#{i}", kind: "savings_rate", target_cents: 10_000, status: "active") }
    sixth = @account.goals.new(name: "G6", kind: "savings_rate", target_cents: 10_000, status: "active")
    refute sixth.valid?
    assert_includes sixth.errors.full_messages.join, I18n.t("activerecord.errors.models.goal.attributes.base.too_many_active")
  end

  test "drafts do not count against the active cap" do
    5.times { @account.goals.create!(name: "d", kind: "savings_rate", target_cents: 10_000, status: "draft") }
    assert @account.goals.new(name: "active", kind: "savings_rate", target_cents: 10_000, status: "active").valid?
  end

  test "goal_checks are idempotent on [goal_id, period_start]" do
    goal = @account.goals.create!(name: "G", kind: "savings_rate", target_cents: 10_000, status: "active")
    week = Date.new(2026, 7, 6)
    @account.goal_checks.create!(goal:, period_start: week, status: "on_track")
    dup = @account.goal_checks.new(goal:, period_start: week, status: "at_risk")
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "abandoning keeps the row (status lifecycle, never destroyed by abandon)" do
    goal = @account.goals.create!(name: "G", kind: "savings_rate", target_cents: 10_000, status: "active")
    Goals::Abandon.call(goal)
    assert goal.reload.persisted?
    assert goal.abandoned?
  end

  test "abandon never reverts an achieved goal" do
    goal = @account.goals.create!(name: "G", kind: "savings_rate", target_cents: 10_000, status: "achieved", achieved_at: Time.current)
    refute Goals::Abandon.call(goal)
    assert goal.reload.achieved?
  end
end
