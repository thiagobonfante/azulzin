require "test_helper"

# One member's weekly budget sweep, end to end (up-tier 03 §4–5, §8): Budgets::Check at
# the member's bands → Notification.record! (one warn + one breach per category per month;
# the kind is in the dedup key so 80→100 escalates, re-crossing is silent) → the D9
# under-budget suggestion, last week only, at most ONE per month across BOTH kinds.
# Deliver stays inert this phase: dashboard rows only, no claim burned.
class Budgets::NotifyMemberJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  JULY = Date.new(2026, 7, 1)

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    @cat     = @account.categories.create!(name: "Restaurantes", monthly_budget_cents: 60_000)
    travel_to Time.utc(2026, 7, 6, 15, 0)   # Monday, 12:00 SP — mid-month, NOT the last week
  end

  def run_for(user = @user) = Budgets::NotifyMemberJob.perform_now(@account.id, user.id)

  def spend!(cents, category: @cat, on: Date.new(2026, 7, 3), card: nil)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                  occurred_on: on, category: category,
                                  bank_account: (card ? nil : @bank), credit_card: card)
  end

  def income!(cents, on: Date.new(2026, 7, 2))
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: cents,
                                  occurred_on: on, bank_account: @bank)
  end

  test "R$ 500 of R$ 600 → one budget_warn; R$ 520 re-run silent; R$ 610 → one budget_breach; next month re-arms" do
    spend!(50_000)   # 83% ≥ warn 80
    assert_difference(-> { Notification.count }, 1) { run_for }

    row = Notification.find_by!(kind: "budget_warn")
    assert_equal @cat, row.subject
    assert_equal JULY, row.period_key
    assert_equal({ "category" => "Restaurantes", "spent_cents" => 50_000,
                   "budget_cents" => 60_000, "left_cents" => 10_000 }, row.payload)
    assert_nil row.whatsapp_sent_at, "dashboard-only phase: Deliver must not burn a claim"

    spend!(2_000)    # 87% — same band, next Monday
    travel_to Time.utc(2026, 7, 13, 15, 0)
    assert_no_difference(-> { Notification.count }) { run_for }

    spend!(9_000)    # 102% — crossed the breach band
    travel_to Time.utc(2026, 7, 20, 15, 0)
    assert_difference(-> { Notification.where(kind: "budget_breach").count }, 1) { run_for }
    assert_equal 1, Notification.where(kind: "budget_warn").count, "the warn row is not re-fired"
    assert_no_difference(-> { Notification.count }) { run_for }

    travel_to Time.utc(2026, 8, 3, 15, 0)   # first Monday of August
    spend!(61_000, on: Date.new(2026, 8, 1))
    assert_difference(-> { Notification.where(kind: "budget_breach").count }, 1) { run_for }
    assert_equal [ JULY, Date.new(2026, 8, 1) ],
                 Notification.where(kind: "budget_breach").order(:period_key).pluck(:period_key)
  end

  test "a card purchase counts toward the budget; an income in the category never does" do
    card = CreditCard.create!(account: @account, institution: @inst,
                              bill_due_day: 10, closing_offset_days: 2)
    spend!(50_000, on: Date.new(2026, 7, 1), card: card)   # July fatura
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 60_000,
                                  occurred_on: Date.new(2026, 7, 2), category: @cat, bank_account: @bank)

    run_for
    assert_equal [ "budget_warn" ], Notification.pluck(:kind),
                 "card spend reaches warn; the income would have pushed it past breach if it counted"
  end

  test "the member's own bands apply (warn at 90 stays silent at 83%)" do
    @user.notification_prefs.update!(budget_warn_percent: 90)
    spend!(50_000)

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "budget_alerts toggle off → no rows for that member" do
    @user.notification_prefs.update!(budget_alerts: false)
    spend!(61_000)

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "two members each get their own row" do
    other = User.create!(email_address: "member@example.com", password: "password123")
    @account.add_member!(other)
    spend!(50_000)

    run_for(@user)
    run_for(other)
    assert_equal [ @user.id, other.id ].sort, Notification.where(kind: "budget_warn").pluck(:user_id).sort
  end

  test "a member no longer in the account gets nothing" do
    spend!(61_000)

    assert_no_difference -> { Notification.count } do
      Budgets::NotifyMemberJob.perform_now(@account.id, users(:english).id)
    end
  end

  # ── The D9 under-budget suggestion ──────────────────────────────────────

  def idle_budget!   # rightsize-eligible: budget R$ 500 vs a R$ 100 median across Apr–Jun
    cat = @account.categories.create!(name: "Assinaturas", monthly_budget_cents: 50_000)
    [ 4, 5, 6 ].each { |m| spend!(10_000, category: cat, on: Date.new(2026, m, 10)) }
    cat
  end

  test "last week + in the blue + savings account → exactly ONE suggestion, surplus preferred over rightsize" do
    travel_to Time.utc(2026, 7, 27, 15, 0)   # the last Monday of July
    BankAccount.create!(account: @account, institution: @inst, kind: "savings")
    income!(100_000)
    spend!(50_000, category: nil)            # sobra R$ 500
    idle_budget!                             # rightsize also eligible — must lose to surplus

    assert_difference(-> { Notification.count }, 1) { run_for }
    row = Notification.find_by!(kind: "surplus_nudge")
    assert_nil row.subject
    assert_equal JULY, row.period_key
    assert_equal 50_000, row.payload["surplus_cents"]
    assert_empty Notification.where(kind: "rightsize_budget"), "never both (D9)"

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "once surplus fired, rightsize cannot fire the same month (one-per-month spans both kinds)" do
    travel_to Time.utc(2026, 7, 27, 15, 0)
    BankAccount.create!(account: @account, institution: @inst, kind: "savings")
    income!(100_000)
    run_for                                  # surplus_nudge recorded

    spend!(200_000, category: nil)           # now deep in the red, but rightsize is eligible
    idle_budget!
    assert_no_difference(-> { Notification.where(kind: %w[surplus_nudge rightsize_budget]).count }) { run_for }
  end

  test "no savings account → rightsize picks the one idle budget, lowering to the median" do
    travel_to Time.utc(2026, 7, 27, 15, 0)
    income!(100_000)                         # in the blue, but nowhere to guardar
    cat = idle_budget!

    assert_difference(-> { Notification.count }, 1) { run_for }
    row = Notification.find_by!(kind: "rightsize_budget")
    assert_equal cat, row.subject
    assert_equal({ "category" => "Assinaturas", "budget_cents" => 50_000, "typical_cents" => 10_000 },
                 row.payload)
  end

  test "an idle budget with only 2 months of history is too young to right-size" do
    travel_to Time.utc(2026, 7, 27, 15, 0)
    income!(100_000)
    cat = @account.categories.create!(name: "Assinaturas", monthly_budget_cents: 50_000)
    [ 5, 6 ].each { |m| spend!(10_000, category: cat, on: Date.new(2026, m, 10)) }

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "in the red → no suggestion at all, even with a savings account and an idle budget" do
    travel_to Time.utc(2026, 7, 27, 15, 0)
    BankAccount.create!(account: @account, institution: @inst, kind: "savings")
    income!(10_000)
    spend!(50_000, category: nil)
    idle_budget!

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "in the blue but below the R$ 50 floor, no savings, no idle budget → silence, not a filler tip" do
    travel_to Time.utc(2026, 7, 27, 15, 0)
    income!(4_000)

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "not the last week → no suggestion however blue the month is" do
    BankAccount.create!(account: @account, institution: @inst, kind: "savings")
    income!(100_000)

    assert_no_difference(-> { Notification.count }) { run_for }   # frozen at Jul 6
  end

  test "surplus_nudges toggle off → no suggestion rows" do
    @user.notification_prefs.update!(surplus_nudges: false)
    travel_to Time.utc(2026, 7, 27, 15, 0)
    BankAccount.create!(account: @account, institution: @inst, kind: "savings")
    income!(100_000)

    assert_no_difference(-> { Notification.count }) { run_for }
  end
end
