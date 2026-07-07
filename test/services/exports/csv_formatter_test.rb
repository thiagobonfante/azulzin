require "test_helper"

class Exports::CsvFormatterTest < ActiveSupport::TestCase
  BOM = "﻿"

  setup do
    @account = accounts(:confirmed)
    inst  = Institution.find_by(code: "260")
    @bank = @account.bank_accounts.create!(institution: inst, nickname: "Corrente")
    category = @account.categories.create!(name: "Alimentação")
    @account.transactions.create!(amount_cents: 12_345, occurred_on: Date.new(2026, 7, 7),
                                  status: "posted", direction: "expense", bank_account: @bank,
                                  merchant: "Padaria São João", category: category,
                                  category_source: "user")
    @ledger = Exports::Ledger.new(@account, from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 31))
  end

  test "pt-BR: leading UTF-8 BOM, ; separator, localized headers and acentos intact" do
    csv = Exports::CsvFormatter.call(@ledger)
    assert csv.start_with?(BOM), "expected a UTF-8 BOM for Excel"
    header, row = csv.delete_prefix(BOM).lines.first(2)
    assert_equal "Data;Mês de competência;Descrição;Categoria;Tipo;Valor;Conta/cartão;Status",
                 header.chomp
    assert_includes row, "Padaria São João"
    assert_includes row, "Alimentação"
    assert_includes row, ";-123,45;"     # localized decimal, signed, no grouping
    assert_includes row, "julho de 2026" # billing month labelled in the locale
  end

  test "en-US: comma separator, BOM still present (acentos need it in any locale)" do
    csv = I18n.with_locale(:"en-US") { Exports::CsvFormatter.call(@ledger) }
    assert csv.start_with?(BOM), "every export carries a BOM — the data has acentos regardless of UI locale"
    header, row = csv.delete_prefix(BOM).lines.first(2)
    assert_equal "Date,Billing month,Description,Category,Type,Amount,Account/card,Status",
                 header.chomp
    assert_includes row, ",-123.45,"
    assert_includes row, "July 2026"
  end

  test "formula-injection: user text starting with = + - @ is neutralized with a leading '" do
    evil = @account.categories.create!(name: "=cmd|'/c calc'!A1")
    @account.transactions.create!(amount_cents: 5_000, occurred_on: Date.new(2026, 7, 8),
                                  status: "posted", direction: "expense", bank_account: @bank,
                                  merchant: "=HYPERLINK(A1)", category: evil,
                                  category_source: "user")
    @account.transactions.create!(amount_cents: 2_000, occurred_on: Date.new(2026, 7, 9),
                                  status: "posted", direction: "expense", bank_account: @bank,
                                  merchant: "+55 11 pizza")

    csv = Exports::CsvFormatter.call(@ledger)
    assert_includes csv, "'=HYPERLINK(A1)",             "description must be prefixed"
    assert_includes csv, "'=cmd|'/c calc'!A1",          "category must be prefixed"
    assert_includes csv, "'+55 11 pizza",               "leading + must be prefixed"
    assert_not_includes csv, ";=HYPERLINK",             "no bare formula cell may survive"
    assert_includes csv, ";-50,00;", "the amount column keeps bare negatives — never guarded"
  end
end
