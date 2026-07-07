require "test_helper"

# The digest assembler (up-tier 04 §1, §4–5): weekly = occurred_on-window spend by
# category (top-3 + outros) + month-to-date sobra + the next-2 bills; monthly = the PRIOR
# month's full hub strip + budget performance. Every number must equal the hub's for the
# same period (shared read models — parity asserted anyway), and an empty period returns
# nil: no row, no push.
class Summaries::BuildTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    travel_to Time.utc(2026, 7, 12, 23, 0)   # Sunday 20:00 SP — the weekly dispatch moment
  end

  def spend!(cents, on:, category: nil, card: nil)
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: cents,
                                  occurred_on: on, category: category,
                                  bank_account: (card ? nil : @bank), credit_card: card)
  end

  def income!(cents, on:)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: cents,
                                  occurred_on: on, bank_account: @bank)
  end

  def category!(name, budget: nil)
    @account.categories.create!(name: name, monthly_budget_cents: budget)
  end

  def bill!(name, day:, cents: 18_240)
    Commitment.create!(account: @account, bank_account: @bank, name: name, kind: "fixed",
                       amount_cents: cents, schedule_day: day, starts_on: Date.new(2026, 7, 1))
  end

  # ── Weekly ────────────────────────────────────────────────────────────────

  test "weekly: window spend by category (top-3 + outros), sobra parity, next-2 bills, Monday period_key" do
    mercado      = category!("Mercado")
    restaurantes = category!("Restaurantes")
    transporte   = category!("Transporte")
    lazer        = category!("Lazer")
    card = CreditCard.create!(account: @account, institution: @inst,
                              bill_due_day: 10, closing_offset_days: 2)

    spend!(42_000, on: Date.new(2026, 7, 8),  category: mercado)
    spend!(31_000, on: Date.new(2026, 7, 10), category: restaurantes)
    spend!(19_000, on: Date.new(2026, 7, 10), category: transporte, card: card)   # card spend counts in ITS week
    spend!(5_000,  on: Date.new(2026, 7, 11), category: lazer)                    # 4th place → outros
    spend!(7_000,  on: Date.new(2026, 7, 12))                                     # uncategorized → outros
    spend!(99_000, on: Date.new(2026, 7, 4),  category: mercado)                  # before the window — ignored
    bill!("Luz", day: 13)
    bill!("Internet", day: 14, cents: 12_000)
    bill!("Água", day: 15)                                                        # 3rd bill → cut at 2

    result = Summaries::Build.call(@account, :weekly)
    assert_equal Date.new(2026, 7, 6), result[:period_key], "the week's Monday, SP-time"

    payload = result[:payload]
    assert_equal 104_000, payload[:spent_cents]
    assert_equal [ { "name" => "Mercado", "cents" => 42_000 },
                   { "name" => "Restaurantes", "cents" => 31_000 },
                   { "name" => "Transporte", "cents" => 19_000 } ], payload[:top_categories]
    assert_equal 12_000, payload[:other_cents], "4th category + uncategorized fold into outros"
    assert_equal [ { "name" => "Luz", "cents" => 18_240 },
                   { "name" => "Internet", "cents" => 12_000 } ], payload[:upcoming]
    assert_equal MonthSummary.new(@account, Date.new(2026, 7, 1)).remaining_cents,
                 payload[:sobra_cents], "hub parity: sobra is THE hub number, not a re-derivation"
  end

  test "weekly: a fatura due in the window is an upcoming bill; its closing is not" do
    card = CreditCard.create!(account: @account, institution: @inst,
                              bill_due_day: 15, closing_offset_days: 2)
    spend!(23_400, on: Date.new(2026, 7, 1), category: category!("Mercado"), card: card)

    payload = Summaries::Build.call(@account, :weekly)[:payload]
    assert_equal [ { "name" => card.display_name, "cents" => 23_400 } ], payload[:upcoming],
                 "due 07-15 is in the look-ahead; closing 07-13 is not a payment"
  end

  test "weekly: zero activity and no upcoming bills → nil (no 'semana parada' push)" do
    spend!(42_000, on: Date.new(2026, 7, 4), category: category!("Mercado"))   # outside the window

    assert_nil Summaries::Build.call(@account, :weekly)
  end

  test "weekly: zero spend but an upcoming bill → a look-ahead-only digest" do
    bill!("Luz", day: 13)

    payload = Summaries::Build.call(@account, :weekly)[:payload]
    assert_equal 0, payload[:spent_cents]
    assert_empty payload[:top_categories]
    assert_equal [ { "name" => "Luz", "cents" => 18_240 } ], payload[:upcoming]
  end

  # ── Monthly ───────────────────────────────────────────────────────────────

  def seed_july!
    @mercado      = category!("Mercado", budget: 250_000)
    @restaurantes = category!("Restaurantes", budget: 50_000)
    @card = CreditCard.create!(account: @account, institution: @inst,
                               bill_due_day: 10, closing_offset_days: 2)
    @savings = BankAccount.create!(account: @account, institution: @inst, kind: "savings")

    income!(850_000, on: Date.new(2026, 7, 5))
    spend!(180_000, on: Date.new(2026, 7, 8),  category: @mercado)
    spend!(60_000,  on: Date.new(2026, 7, 15), category: @restaurantes)
    spend!(60_000,  on: Date.new(2026, 7, 20))                                  # uncategorized
    spend!(50_000,  on: Date.new(2026, 7, 3),  category: @mercado, card: @card) # July fatura
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 100_000,
                                  occurred_on: Date.new(2026, 7, 25), bank_account: @bank,
                                  transfer_to_bank_account: @savings)            # guardado
  end

  test "monthly on the 1st: the PRIOR month's full hub strip, with parity, top categories and budget counts" do
    seed_july!
    travel_to Time.utc(2026, 8, 1, 11, 0)   # 08:00 SP on the 1st — the dispatch moment

    result = Summaries::Build.call(@account, :monthly)
    assert_equal Date.new(2026, 7, 1), result[:period_key]

    payload = result[:payload]
    hub     = MonthSummary.new(@account, Date.new(2026, 7, 1))
    assert_equal "2026-07-01", payload[:month]
    assert_equal hub.entradas_cents,  payload[:in_cents]
    assert_equal hub.saidas_cents,    payload[:out_cents]
    assert_equal hub.faturas_cents,   payload[:bills_cents]
    assert_equal hub.remaining_cents, payload[:sobra_cents]
    assert_equal hub.guardado_cents,  payload[:saved_cents]
    assert_equal 400_000, payload[:sobra_cents], "850 in − 300 out − 50 fatura − 100 saved"

    assert_equal [ { "name" => "Mercado", "cents" => 230_000 },       # card spend at billing_month (D4)
                   { "name" => "Restaurantes", "cents" => 60_000 } ], payload[:top_categories]
    assert_equal 60_000, payload[:other_cents]
    assert_equal 1, payload[:budget_within], "Mercado stayed under 2.500; Restaurantes blew 500"
    assert_equal 2, payload[:budget_total]
  end

  test "monthly: no budgets set → no budget counts in the payload (the line skips)" do
    income!(100_000, on: Date.new(2026, 7, 5))
    travel_to Time.utc(2026, 8, 1, 11, 0)

    payload = Summaries::Build.call(@account, :monthly)[:payload]
    assert_not payload.key?(:budget_total)
    assert_not payload.key?(:budget_within)
  end

  test "monthly boundary is São Paulo's, not UTC's: 01:00 UTC on the 1st still recaps the month before last" do
    income!(120_000, on: Date.new(2026, 6, 10))
    income!(850_000, on: Date.new(2026, 7, 5))

    travel_to Time.utc(2026, 8, 1, 1, 0)     # already Aug 1 UTC, still Jul 31 22:00 SP
    result = Summaries::Build.call(@account, :monthly)
    assert_equal Date.new(2026, 6, 1), result[:period_key], "SP is still in July; the closed month is June"
    assert_equal 120_000, result[:payload][:in_cents]

    travel_to Time.utc(2026, 8, 1, 11, 0)    # 08:00 SP on the 1st
    result = Summaries::Build.call(@account, :monthly)
    assert_equal Date.new(2026, 7, 1), result[:period_key]
    assert_equal 850_000, result[:payload][:in_cents]
  end

  test "monthly: a month with zero movement → nil" do
    travel_to Time.utc(2026, 8, 1, 11, 0)

    assert_nil Summaries::Build.call(@account, :monthly)
  end
end
