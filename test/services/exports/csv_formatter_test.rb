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
    assert csv.start_with?(BOM), "expected a UTF-8 BOM for pt-BR Excel"
    header, row = csv.delete_prefix(BOM).lines.first(2)
    assert_equal "Data;Mês de competência;Descrição;Categoria;Tipo;Valor;Conta/cartão;Status",
                 header.chomp
    assert_includes row, "Padaria São João"
    assert_includes row, "Alimentação"
    assert_includes row, ";-123,45;"     # localized decimal, signed, no grouping
    assert_includes row, "julho de 2026" # billing month labelled in the locale
  end

  test "en-US: comma separator and no BOM" do
    csv = I18n.with_locale(:"en-US") { Exports::CsvFormatter.call(@ledger) }
    assert_not csv.start_with?(BOM), "en export must not carry a BOM"
    header, row = csv.lines.first(2)
    assert_equal "Date,Billing month,Description,Category,Type,Amount,Account/card,Status",
                 header.chomp
    assert_includes row, ",-123.45,"
    assert_includes row, "July 2026"
  end
end
