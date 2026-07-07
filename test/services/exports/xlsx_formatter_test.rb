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
    ledger = Exports::Ledger.new(@account, from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 31))
    @xlsx  = Exports::XlsxFormatter.call(ledger)
  end

  def sheet_xml
    Zip::File.open_buffer(StringIO.new(@xlsx)) do |zip|
      return zip.read("xl/worksheets/sheet1.xml").force_encoding(Encoding::UTF_8)
    end
  end

  test "money cells are real numbers a spreadsheet can sum, and the totals row matches" do
    xml = sheet_xml
    assert_includes xml, "<v>5000.0</v>",   "income cell should be numeric"
    assert_includes xml, "<v>-123.45</v>",  "expense cell should be numeric and signed"
    assert_includes xml, "<v>4876.55</v>",  "totals row should equal the exact BigDecimal sum"
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
