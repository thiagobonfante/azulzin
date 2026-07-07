require "test_helper"
require "zip"

class Exports::XlsxFormatterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:confirmed)
    inst  = Institution.find_by(code: "260")
    @bank = @account.bank_accounts.create!(institution: inst, nickname: "Corrente")
    @account.transactions.create!(amount_cents: 12_345, occurred_on: Date.new(2026, 7, 7),
                                  status: "posted", direction: "expense", bank_account: @bank,
                                  merchant: "Padaria São João")
    @account.transactions.create!(amount_cents: 500_000, occurred_on: Date.new(2026, 7, 1),
                                  status: "posted", direction: "income", bank_account: @bank,
                                  description: "Salário")
    savings = @account.bank_accounts.create!(institution: inst, nickname: "Caixinha", kind: "savings")
    @account.transactions.create!(amount_cents: 100_000, occurred_on: Date.new(2026, 7, 2),
                                  status: "posted", direction: "transfer", bank_account: @bank,
                                  transfer_to_bank_account: savings)
    ledger = Exports::Ledger.new(@account, from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 31))
    @xlsx  = Exports::XlsxFormatter.call(ledger)
  end

  def sheet_xml
    Zip::File.open_buffer(StringIO.new(@xlsx)) do |zip|
      return zip.read("xl/worksheets/sheet1.xml").force_encoding(Encoding::UTF_8)
    end
  end

  test "money cells are real numbers a spreadsheet can sum" do
    xml = sheet_xml
    assert_includes xml, "<v>5000.0</v>",   "income cell should be numeric"
    assert_includes xml, "<v>-123.45</v>",  "expense cell should be numeric and signed"
    assert_includes xml, "<v>-1000.0</v>",  "transfer cell should be numeric and signed"
  end

  test "totals block is labelled per direction and the result excludes transfers" do
    xml = sheet_xml
    assert_includes xml, "Entradas"
    assert_includes xml, "Saídas"
    assert_includes xml, "Transferências"
    assert_includes xml, "Resultado"
    assert_equal 2, xml.scan("<v>5000.0</v>").size,  "Entradas figure (data cell + totals row)"
    assert_equal 2, xml.scan("<v>-123.45</v>").size, "Saídas figure (data cell + totals row)"
    assert_equal 2, xml.scan("<v>-1000.0</v>").size, "Transferências figure (data cell + totals row)"
    assert_includes xml, "<v>4876.55</v>", "Resultado = entradas − saídas"
    assert_not_includes xml, "<v>3876.55</v>", "the transfer must not deflate the result"
  end

  test "localized header row is present and frozen" do
    xml = sheet_xml
    assert_includes xml, "Mês de competência"
    assert_includes xml, "Conta/cartão"
    assert_match(/<pane[^>]*state="frozen"/, xml)
  end

  test "the package is a valid non-empty zip" do
    assert @xlsx.start_with?("PK"), "xlsx must be a zip container"
    assert_operator @xlsx.bytesize, :>, 1_000
  end
end
