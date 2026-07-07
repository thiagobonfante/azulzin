require "test_helper"
require "pdf-reader"

class Exports::PdfFormatterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:confirmed)
    inst  = Institution.find_by(code: "260")
    @bank = @account.bank_accounts.create!(institution: inst, nickname: "Corrente")
  end

  def txn(**attrs)
    @account.transactions.create!({ amount_cents: 12_345, occurred_on: Date.new(2026, 7, 7),
                                    status: "posted", direction: "expense",
                                    bank_account: @bank }.merge(attrs))
  end

  def pdf_text(from: Date.new(2026, 6, 1), to: Date.new(2026, 7, 31))
    ledger = Exports::Ledger.new(@account, from: from, to: to)
    pdf    = Exports::PdfFormatter.call(ledger)
    assert pdf.start_with?("%PDF"), "must render a PDF document"
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end

  test "renders account header, period, month groups, category and labelled totals — localized" do
    category = @account.categories.create!(name: "Alimentação")
    txn(merchant: "Padaria São João", category: category, category_source: "user")
    txn(direction: "income", description: "Salário", amount_cents: 500_000,
        occurred_on: Date.new(2026, 6, 10))
    savings = @account.bank_accounts.create!(institution: Institution.find_by(code: "260"),
                                             nickname: "Caixinha", kind: "savings")
    txn(direction: "transfer", amount_cents: 100_000, transfer_to_bank_account: savings,
        occurred_on: Date.new(2026, 7, 5))

    text = pdf_text
    assert_includes text, @account.name
    assert_includes text, "Período: 01/06/2026 a 31/07/2026"
    assert_includes text, "junho de 2026"      # month group headers
    assert_includes text, "julho de 2026"
    assert_includes text, "Padaria São João"   # acentos render (Windows-1252 font)
    assert_includes text, "Totais por categoria"
    assert_includes text, "Alimentação"
    assert_includes text, "R$ 123,45"
    assert_includes text, "Entradas: R$ 5.000,00"
    assert_includes text, "Saídas: R$ 123,45"
    assert_includes text, "Transferências: R$ 1.000,00"
    assert_includes text, "Resultado do período: R$ 4.876,55",
                    "the transfer is neutral — it must not deflate the result"
  end

  test "text a Windows-1252 font cannot draw (emoji) is stripped, not crashed on" do
    txn(merchant: "mercado 🛒 da esquina")
    text = pdf_text
    assert_match(/mercado\s+da esquina/, text)
  end

  test "an empty export still renders, saying the period has no movements" do
    text = pdf_text(from: nil, to: nil)
    assert_includes text, "Nenhum movimento no período."
    assert_includes text, "Resultado do período: R$ 0,00"
  end
end
