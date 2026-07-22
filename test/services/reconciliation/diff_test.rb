require "test_helper"

# The deterministic matcher (.plans/credit-cards 03 §2) with the adversarial fixtures the
# plan names: same-amount same-day pairs and estornos must never cross-match.
class Reconciliation::DiffTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @card    = CreditCard.create!(account: @account, institution: Institution.find_by!(code: "260"),
                                  bill_due_day: 10, closing_offset_days: 7)
    @month   = Date.new(2026, 7, 1)
  end

  def txn!(merchant, cents, on:, direction: "expense", installment: nil, commitment: nil)
    @account.transactions.create!(
      merchant: merchant, direction: direction, status: "posted", credit_card: @card,
      amount_cents: cents, occurred_on: on, billing_month: @month, billing_month_manual: true,
      installment_number: installment, commitment: commitment)
  end

  def row(desc, cents, on:, direction: "expense", installment: nil)
    Reconciliation::Row.new(date: on, description: desc, amount_cents: cents,
                            direction: direction, installment: installment)
  end

  def diff(rows)
    Reconciliation::Diff.call(rows: rows,
      scope: Reconciliation::CardBillScope.new(credit_card: @card, month: @month))
  end

  test "REC-01 shape: one missing, one ours-only, one typo mismatch, rest matched" do
    matched  = txn!("Mercado Central", 12_500, on: Date.new(2026, 6, 20))
    ours     = txn!("Compra Fantasma", 30_000, on: Date.new(2026, 6, 22))
    typo     = txn!("Padaria Sol", 8_990, on: Date.new(2026, 6, 25))

    result = diff([
      row("MERCADO CENTRAL", 12_500, on: Date.new(2026, 6, 21)),   # 1 day off, same cents → matched
      row("FARMACIA NOVA",   4_500,  on: Date.new(2026, 6, 23)),   # only at the bank → create
      row("PADARIA SOL",     8_890,  on: Date.new(2026, 6, 25))    # 1 centavo... 100¢ off → fix
    ])

    assert_equal [ matched ], result.matched.map(&:last)
    assert_equal [ "FARMACIA NOVA" ], result.only_in_source.map(&:description)
    assert_equal [ ours ], result.only_in_app
    assert_equal [ [ "PADARIA SOL", typo ] ], result.amount_mismatch.map { |r, t| [ r.description, t ] }
  end

  test "adversarial: two same-amount same-day rows pair by description, never crossed" do
    uber   = txn!("Uber Viagem", 2_500, on: Date.new(2026, 6, 18))
    padoca = txn!("Padoca da Vila", 2_500, on: Date.new(2026, 6, 18))

    result = diff([
      row("PADOCA DA VILA SAO PAULO", 2_500, on: Date.new(2026, 6, 18)),
      row("UBER *VIAGEM",             2_500, on: Date.new(2026, 6, 18))
    ])

    pairs = result.matched.to_h { |r, t| [ t, r.description ] }
    assert_equal "UBER *VIAGEM", pairs[uber]
    assert_equal "PADOCA DA VILA SAO PAULO", pairs[padoca]
  end

  test "adversarial: an estorno (income) never matches an expense of the same cents" do
    txn!("Loja Devolvida", 9_900, on: Date.new(2026, 6, 15), direction: "income")

    result = diff([ row("LOJA DEVOLVIDA", 9_900, on: Date.new(2026, 6, 15)) ])   # expense side

    assert_empty result.matched
    assert_equal 1, result.only_in_source.size
    assert_equal 1, result.only_in_app.size
  end

  test "parcel lines must agree on k" do
    plan = @account.commitments.create!(kind: "installment", name: "Notebook", credit_card: @card,
                                        amount_cents: 10_000, total_cents: 30_000, installments_count: 3,
                                        starts_on: @month, schedule_kind: "fixed_day")
    parcel2 = txn!("Notebook", 10_000, on: Date.new(2026, 6, 10), installment: 2, commitment: plan)

    hit  = diff([ row("NOTEBOOK PARC 02/03", 10_000, on: Date.new(2026, 6, 10), installment: "02/03") ])
    miss = diff([ row("NOTEBOOK PARC 03/03", 10_000, on: Date.new(2026, 6, 10), installment: "03/03") ])

    assert_equal [ parcel2 ], hit.matched.map(&:last)
    assert_empty miss.matched
  end

  test "a date beyond ±3 days never matches; an undated row surfaces as only-in-source" do
    txn!("Mercado Central", 12_500, on: Date.new(2026, 6, 20))

    result = diff([
      row("MERCADO CENTRAL", 12_500, on: Date.new(2026, 6, 26)),   # 6 days off
      Reconciliation::Row.new(date: nil, description: "SEM DATA", amount_cents: 12_500, direction: "expense")
    ])

    assert_empty result.matched
    assert_equal %w[MERCADO\ CENTRAL SEM\ DATA], result.only_in_source.map(&:description).sort
  end
end
