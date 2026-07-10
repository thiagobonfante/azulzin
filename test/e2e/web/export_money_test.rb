require "test_helpers/e2e/pipeline_case"
require "csv"

# WEB-EXP-01/04: the export is the user's money leaving the app — its numbers must sum to
# the ledger exactly; a WhatsApp receipt must outlive the media purge (.plans/e2e/05 §7).
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
end
