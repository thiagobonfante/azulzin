require "test_helpers/e2e/pipeline_case"
require "csv"
require "zip"

# WEB-EXP-01/02/03/04: the export is the user's money leaving the app — its numbers must sum
# to the ledger exactly (CSV and xlsx), it must NEVER carry another account's rows, and a
# WhatsApp receipt must outlive the media purge (.plans/e2e/05 §7).
class E2E::WebExportMoneyTest < E2E::PipelineCase
  test "CSV export: parsed rows sum to the calibrated ledger to the centavo" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_as s.owner

    get exports_url, params: { preset: "current_month", format: "csv" }
    assert_response :success

    # pt-BR CSV: BOM-prefixed, ;-separated, signed locale-formatted amounts.
    rows = CSV.parse(response.body.delete_prefix("\xEF\xBB\xBF"), headers: true, col_sep: ";")
    assert rows.count.positive?
    amount_header = I18n.t("exports.ledger.headers.amount", locale: :"pt-BR")

    total_abs = rows.sum { |r| Money.to_cents(r[amount_header].to_s.delete("-")) }
    # entradas 500.000 + saídas 261.279 + guardado 30.000 — every current-month row, exact.
    assert_equal 500_000 + 261_279 + 30_000, total_abs
  end

  # WEB-EXP-02 — xlsx is the form's first format; its money cells are real numbers. Parse the
  # workbook back to the centavo, same ledger as the CSV test.
  test "xlsx export: the amount cells sum to the calibrated ledger to the centavo" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_as s.owner

    get exports_url, params: { preset: "current_month", format: "xlsx" }
    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type

    total_abs = xlsx_amount_cents(response.body).sum(&:abs)
    assert_equal 500_000 + 261_279 + 30_000, total_abs, "every current-month row, exact, out of the .xlsx"
  end

  # WEB-EXP-03 — tenancy: an export never carries another account's rows. Build a couple's
  # account AND a stranger's, export the couple's, and prove the stranger is absent.
  test "the export is scoped to the signed-in account and never leaks another's rows" do
    couple   = E2E::Scenario.build(:solo_basic)
    couple.expense(merchant: "Padaria da Familia", category: "Mercado", instrument: couple.itau,
                   cents: 4_200, on: Date.current)
    stranger = E2E::Scenario.build(:solo_basic)
    stranger.expense(merchant: "Segredo do Estranho", category: "Mercado", instrument: stranger.itau,
                     cents: 9_900, on: Date.current)

    sign_in_as couple.owner
    get exports_url, params: { preset: "current_month", format: "csv" }
    body = response.body.delete_prefix("\xEF\xBB\xBF")

    assert_includes body, "Padaria da Familia", "the couple's own row is present"
    assert_not_includes body, "Segredo do Estranho", "the stranger's row must never appear"
    rows = CSV.parse(body, headers: true, col_sep: ";")
    amount_header = I18n.t("exports.ledger.headers.amount", locale: :"pt-BR")
    assert_equal 4_200, rows.sum { |r| Money.to_cents(r[amount_header].to_s.delete("-")) }
  end

  test "a WhatsApp receipt survives the 60-day media purge" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    bytes = File.binread(Rails.root.join("test/fixtures/files/receipt.jpg"))
    media = { data: Base64.strict_encode64(bytes), mimetype: "image/jpeg", filename: "receipt.jpg" }

    msg = nil
    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Mercado Nota", method: "debito",
                                    instrument: "itau", modality: "image")
    with_canned_ai(receipt: receipt) do
      msg = wa_inject(s.jid, "", type: "image", media: media)
      drain_jobs!
    end
    txn = s.account.transactions.sole
    assert txn.receipt.attached?

    travel 61.days
    WhatsappRetentionJob.perform_now
    drain_jobs!

    assert txn.reload.receipt.attached?, "the receipt copy must outlive the WA purge"
    assert_equal bytes.bytesize, txn.receipt.blob.byte_size
    assert_nothing_raised { txn.receipt.blob.download }
  end

  private

  # Amount cells (column F) of the ledger DATA rows only, in cents. A data row is identified by
  # its column-A cell being a numeric date serial (no `t` attr) — the header and bold totals
  # rows carry a STRING in column A, so they're skipped. Money cells hold reais as real numbers.
  def xlsx_amount_cents(bytes)
    cents = []
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      doc = Nokogiri::XML(zip.get_entry("xl/worksheets/sheet1.xml").get_input_stream.read)
      doc.remove_namespaces!
      doc.xpath("//row").each do |row|
        a = row.at_xpath("./c[starts-with(@r,'A')]")
        next unless a && a["t"].nil? && a.at_xpath("./v")   # A is a date serial → a data row
        v = row.at_xpath("./c[starts-with(@r,'F')]/v")
        cents << (BigDecimal(v.text) * 100).round if v
      end
    end
    cents
  end
end
