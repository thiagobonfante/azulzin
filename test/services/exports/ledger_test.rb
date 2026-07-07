require "test_helper"

class Exports::LedgerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:confirmed)
    inst     = Institution.find_by(code: "260")
    @bank    = @account.bank_accounts.create!(institution: inst, nickname: "Corrente")
    @savings = @account.bank_accounts.create!(institution: inst, nickname: "Caixinha", kind: "savings")
    @card    = @account.credit_cards.create!(institution: inst, nickname: "Roxinho")
  end

  def txn(**attrs)
    @account.transactions.create!({ amount_cents: 1_000, occurred_on: Date.new(2026, 7, 7),
                                    status: "posted", direction: "expense",
                                    bank_account: @bank }.merge(attrs))
  end

  def rows(from: Date.new(2026, 1, 1), to: Date.new(2026, 12, 31))
    Exports::Ledger.new(@account, from: from, to: to).rows
  end

  test "rows are ordered by occurred_on and filtered to the range" do
    txn(merchant: "depois",   occurred_on: Date.new(2026, 7, 20))
    txn(merchant: "antes",    occurred_on: Date.new(2026, 7, 1))
    txn(merchant: "de fora",  occurred_on: Date.new(2025, 12, 31))
    assert_equal %w[antes depois], rows.map(&:description)
  end

  test "an unbounded range exports everything" do
    txn(merchant: "antiga", occurred_on: Date.new(2020, 1, 1))
    txn(merchant: "atual")
    assert_equal %w[antiga atual], Exports::Ledger.new(@account).rows.map(&:description)
  end

  test "soft-deleted and rejected/superseded rows never export" do
    txn(merchant: "fica")
    txn(merchant: "rejeitada",  status: "rejected")
    txn(merchant: "superada",   status: "superseded")
    txn(merchant: "pendente",   status: "pending_review")
    txn(merchant: "apagada").soft_delete!(by: nil)
    assert_equal %w[fica], rows.map(&:description)
  end

  test "another account's data never appears" do
    other_bank = accounts(:english).bank_accounts.create!(institution: Institution.find_by(code: "260"))
    accounts(:english).transactions.create!(amount_cents: 999, occurred_on: Date.new(2026, 7, 7),
                                            status: "posted", direction: "expense",
                                            bank_account: other_bank, merchant: "alheia")
    txn(merchant: "minha")
    assert_equal %w[minha], rows.map(&:description)
  end

  test "amounts are signed: income in, expense and transfer out" do
    txn(direction: "income", amount_cents: 5_000, description: "Salário", merchant: nil)
    txn(direction: "expense", amount_cents: 1_234)
    txn(direction: "transfer", amount_cents: 2_000, transfer_to_bank_account: @savings)
    assert_equal [ 5_000, -1_234, -2_000 ],
                 rows.sort_by { |r| -r.amount_cents }.map(&:amount_cents)
    assert_equal 1_766, Exports::Ledger.new(@account).total_cents
  end

  test "category name is a history snapshot — it survives the category's soft delete" do
    category = @account.categories.create!(name: "Mercado")
    txn(merchant: "padaria", category: category, category_source: "user")
    category.soft_delete!(by: nil)
    assert_equal "Mercado", rows.first.category
  end

  test "instrument column names the account or card; transfers show the route" do
    txn(merchant: "no cartão", credit_card: @card, bank_account: nil)
    txn(direction: "transfer", transfer_to_bank_account: @savings, occurred_on: Date.new(2026, 7, 8))
    assert_equal [ "Roxinho", "Corrente → Caixinha" ], rows.map(&:instrument)
  end

  test "kind and status labels are localized" do
    txn(merchant: "qualquer")
    assert_equal "Saída",   rows.first.kind
    assert_equal "Lançado", rows.first.status
    I18n.with_locale(:"en-US") do
      assert_equal "Expense",  rows.first.kind
      assert_equal "Recorded", rows.first.status
    end
  end
end
