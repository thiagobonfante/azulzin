require "test_helper"

class Imports::ParsersTest < ActiveSupport::TestCase
  # ── FormatDetector ────────────────────────────────────────────────────────
  test "detects PDF by magic bytes even with no extension" do
    assert_equal "pdf", Imports::FormatDetector.call("%PDF-1.7\n...binary...", filename: "fatura_por_email")
  end

  test "detects OFX by header" do
    assert_equal "ofx", Imports::FormatDetector.call(ofx_bytes, filename: "x.ofx")
  end

  test "detects CSV by header even when mislabeled" do
    assert_equal "csv", Imports::FormatDetector.call(csv_bytes, filename: "x.xls")
  end

  test "returns nil for random binary" do
    assert_nil Imports::FormatDetector.call("\x00\x01\x02\x03not a document".b, filename: "x.bin")
  end

  # ── CsvParser ─────────────────────────────────────────────────────────────
  test "parses Nubank dot-decimal amounts to positive cents with direction" do
    rows = Imports::CsvParser.call(csv_bytes)["rows"]
    debit = rows.find { it["external_id"] == "11111111-1111-4111-8111-111111111111" }
    assert_equal 1190, debit["amount_cents"]
    assert_equal "out", debit["direction"]
    assert_equal "2026-06-02", debit["date"]
    credit = rows.find { it["direction"] == "in" }
    assert_equal 500000, credit["amount_cents"]
  end

  test "pt-BR decimal sniff kicks in for semicolon 1.234,56 files" do
    csv = "Data;Valor;Descrição\n15/06/2026;1.234,56;Aluguel\n"
    row = Imports::CsvParser.call(csv)["rows"].first
    assert_equal 123456, row["amount_cents"]
  end

  test "keeps the Identificador as external_id and bullets verbatim" do
    csv = "Data,Valor,Identificador,Descrição\n02/06/2026,-10.00,abc-123,Pix •••.456.789-••\n"
    row = Imports::CsvParser.call(csv)["rows"].first
    assert_equal "abc-123", row["external_id"]
    assert_includes row["description"], "•••"
  end

  test "detects CSV whose header sits behind preamble lines (Bradesco-style)" do
    bytes = "Extrato Mensal;;;\nData;Lançamento;Crédito (R$);Débito (R$)\n01/06/2026;X;;10,00\n"
    assert_equal "csv", Imports::FormatDetector.call(bytes, filename: "extrato.csv")
  end

  test "preamble + split credit/debit columns parse with forced directions" do
    csv = <<~CSV
      Extrato de: Conta Corrente;;;;;
      Data;Lançamento;Dcto.;Crédito (R$);Débito (R$);Saldo (R$)
      01/06/2026;PAGTO ELETRON COPEL;123;;317,41;1.000,00
      03/06/2026;TED RECEBIDA;456;4.802,58;0,00;5.802,58
    CSV
    rows = Imports::CsvParser.call(csv)["rows"]
    copel = rows.find { it["description"].include?("COPEL") }
    assert_equal 31741, copel["amount_cents"]
    assert_equal "out", copel["direction"]
    ted = rows.find { it["description"].include?("TED") } # "0,00" débito placeholder ≠ a debit
    assert_equal 480258, ted["amount_cents"]
    assert_equal "in", ted["direction"]
  end

  test "a malformed CSV raises ParseError (visible failure, never a stuck import)" do
    assert_raises(Imports::ParseError) do
      Imports::CsvParser.call("Data,Valor,Descrição\n01/06/2026,-10.00,\"unclosed\n")
    end
  end

  test "unparseable date keeps the row and flags date_unparsed" do
    csv = "Data,Valor,Descrição\nnot-a-date,-10.00,X\n"
    row = Imports::CsvParser.call(csv)["rows"].first
    assert_nil row["date"]
    assert_includes row["signals"], "date_unparsed"
  end

  test "raises ParseError when no date/amount columns" do
    assert_raises(Imports::ParseError) { Imports::CsvParser.call("Foo,Bar\n1,2\n") }
  end

  # ── OfxParser ─────────────────────────────────────────────────────────────
  test "parses account identity keeping the check-digit dash" do
    meta = Imports::OfxParser.call(ofx_bytes)["meta"]
    assert_equal "0260", meta["acct"]["bank_id"]
    assert_equal "1", meta["acct"]["branch_id"]
    assert_equal "9100349-6", meta["acct"]["acct_id"]
    assert_equal "CHECKING", meta["acct"]["acct_type"]
  end

  test "LEDGERBAL is not clobbered by a BALLIST BAL amount" do
    meta = Imports::OfxParser.call(ofx_bytes)["meta"]
    assert_equal 357625, meta["ledger_balance_cents"] # NOT 123 from the BALLIST BAL
    assert_equal "2026-06-30", meta["ledger_balance_as_of"]
    assert_equal "2026-06-01", meta["period_start"]
    assert_equal "2026-06-30", meta["period_end"]
  end

  test "strips the bracket timezone suffix and parses TRNAMT via BigDecimal" do
    rows = Imports::OfxParser.call(ofx_bytes)["rows"]
    assert_equal 3, rows.size
    credit = rows.find { it["external_id"] == "33333333-3333-4333-8333-333333333333" }
    assert_equal "2026-06-04", credit["date"]
    assert_equal 500000, credit["amount_cents"]
    assert_equal "in", credit["direction"]
  end

  test "FITID equals the CSV Identificador (cross-format dedupe key)" do
    ofx_ids = Imports::OfxParser.call(ofx_bytes)["rows"].map { it["external_id"] }
    csv_ids = Imports::CsvParser.call(csv_bytes)["rows"].map { it["external_id"] }
    assert_equal ofx_ids.sort, csv_ids.sort
  end

  test "SGML unclosed leaf tags parse identically to closed ones" do
    closed = <<~OFX
      <OFX><BANKMSGSRSV1><STMTRS>
      <BANKACCTFROM><BANKID>0260</BANKID><ACCTID>9100349-6</ACCTID><ACCTTYPE>CHECKING</ACCTTYPE></BANKACCTFROM>
      <BANKTRANLIST>
      <STMTTRN><DTPOSTED>20260602</DTPOSTED><TRNAMT>-11.90</TRNAMT><FITID>a1</FITID><MEMO>PADARIA</MEMO></STMTTRN>
      </BANKTRANLIST>
      <LEDGERBAL><BALAMT>3576.25</BALAMT><DTASOF>20260630</DTASOF></LEDGERBAL>
      </STMTRS></BANKMSGSRSV1></OFX>
    OFX
    unclosed = <<~OFX
      <OFX><BANKMSGSRSV1><STMTRS>
      <BANKACCTFROM><BANKID>0260<ACCTID>9100349-6<ACCTTYPE>CHECKING</BANKACCTFROM>
      <BANKTRANLIST>
      <STMTTRN><DTPOSTED>20260602<TRNAMT>-11.90<FITID>a1<MEMO>PADARIA</STMTTRN>
      </BANKTRANLIST>
      <LEDGERBAL><BALAMT>3576.25<DTASOF>20260630</LEDGERBAL>
      </STMTRS></BANKMSGSRSV1></OFX>
    OFX
    a = Imports::OfxParser.call(closed)
    b = Imports::OfxParser.call(unclosed)
    assert_equal a["meta"], b["meta"]
    assert_equal a["rows"], b["rows"]
    assert_equal 357625, b["meta"]["ledger_balance_cents"]
    assert_equal "a1", b["rows"].first["external_id"]
  end

  private

  def ofx_bytes = file_fixture("imports/nubank.ofx").read
  def csv_bytes = file_fixture("imports/sample.csv").read
end
