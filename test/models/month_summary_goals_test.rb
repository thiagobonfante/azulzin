require "test_helper"

# The pay-yourself-first money-correctness heart (.plans/goals 07 §1.3, joins the 01 §8 trap list):
# an unpaid savings commitment reduces sobra via projected_guardado; paying it moves the amount into
# guardado with sobra UNCHANGED. Savings-kind commitments are never counted as spending (debit).
class MonthSummaryGoalsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @account  = users(:confirmed).account
    @inst     = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, kind: "checking", nickname: "Conta")
    @caixinha = @account.bank_accounts.create!(institution: @inst, kind: "savings",  nickname: "Caixinha")
    @month    = Date.new(2026, 7, 1)
    travel_to Time.utc(2026, 7, 15, 12)   # mid-month → :current so projection terms apply
  end

  teardown { travel_back }

  def savings_commitment(cents)
    @account.commitments.create!(kind: "savings", bank_account: @checking, amount_cents: cents,
                                 name: "Meta: Carro", starts_on: @month, schedule_day: 5, schedule_kind: "fixed_day")
  end

  def pay!(commitment, cents)
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: cents,
                                  bank_account: @checking, transfer_to_bank_account: @caixinha,
                                  commitment:, occurred_on: Date.new(2026, 7, 15),
                                  billing_month: @month, billing_month_manual: true)
  end

  test "an unpaid savings commitment reduces sobra via projected_guardado, not saídas" do
    savings_commitment(100_000)
    s = MonthSummary.new(@account, @month)
    assert_equal 100_000, s.projected_guardado_cents
    assert_equal 0,       s.saidas_cents               # savings kind excluded from saídas/debit commitments
    assert_equal 0,       s.guardado_cents             # nothing posted yet
    assert_equal(-100_000, s.remaining_cents)          # entradas 0 − … − projected_guardado
    assert_equal 100_000, s.a_pagar_cents              # it IS to pay this month
  end

  test "paying the goal occurrence mid-month leaves sobra UNCHANGED (the named invariant)" do
    sav = savings_commitment(100_000)
    before = MonthSummary.new(@account, @month).remaining_cents

    pay!(sav, 100_000)

    after = MonthSummary.new(@account, @month)
    assert_equal 100_000, after.guardado_cents             # moved into guardado
    assert_equal 0,       after.projected_guardado_cents   # occurrence cleared
    assert_equal before,  after.remaining_cents            # INVARIANT: sobra unchanged at pay time
  end

  test "a transfer beyond the occurrence reduces sobra by exactly the extra (no double-count)" do
    sav = savings_commitment(100_000)
    before = MonthSummary.new(@account, @month).remaining_cents   # −100_000

    pay!(sav, 130_000)   # paid 30_000 more than the scheduled contribution

    after = MonthSummary.new(@account, @month)
    assert_equal 130_000, after.guardado_cents
    assert_equal 0,       after.projected_guardado_cents
    assert_equal before - 30_000, after.remaining_cents          # only the extra reduces sobra
  end

  test "a partial transfer smaller than the occurrence clears the projection (accepted deviation)" do
    sav = savings_commitment(100_000)
    before = MonthSummary.new(@account, @month).remaining_cents   # −100_000

    pay!(sav, 60_000)   # paid less than the scheduled contribution

    after = MonthSummary.new(@account, @month)
    assert_equal 60_000, after.guardado_cents
    assert_equal 0,      after.projected_guardado_cents          # existence-based paid_in? clears it
    assert_equal before + 40_000, after.remaining_cents          # sobra rises by the unpaid remainder (07 §1.3)
  end

  test "regular debit commitments still count as saídas (savings exclusion didn't break debit)" do
    @account.commitments.create!(kind: "fixed", bank_account: @checking, amount_cents: 200_000,
                                 name: "Aluguel", starts_on: @month, schedule_day: 5, schedule_kind: "fixed_day")
    s = MonthSummary.new(@account, @month)
    assert_equal 200_000, s.saidas_cents               # regular debit commitment still projected into saídas
    assert_equal 0,       s.projected_guardado_cents
  end
end
