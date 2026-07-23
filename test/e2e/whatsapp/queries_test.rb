require "test_helpers/e2e/pipeline_case"

# WA-QRY: read-only queries must answer with exactly the numbers the web shows for the
# same frozen scenario (.plans/e2e/03 §3). Expected strings are computed from the pack's
# calibrated constants, never by re-calling the service under test.
class E2E::WhatsappQueriesTest < E2E::PipelineCase
  # WA-QRY-01
  test "quanto tenho: balance lines carry each account's derived balance" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!

    ask_query(s, "account_balance", "quanto tenho nas contas?")

    body = assert_wa_reply(s.jid)
    assert_includes body, s.itau.display_name
    assert_brl 250_000, body     # itau derived (pack-calibrated)
    assert_brl 520_000, body     # savings_account derived
    assert_brl 770_000, body     # total
  end

  # WA-QRY-02
  test "como tá a fatura: open bill equals the pack's card spend" do
    s = E2E::Scenario.build(:cards_billing).wa_verified!
    open_month = s.nubank_card.current_open_bill_month
    expected = s.nubank_card.bill_cents(open_month)

    ask_query(s, "card_bill", "como tá a fatura?")

    body = assert_wa_reply(s.jid, includes: [ s.nubank_card.display_name ])
    assert_brl expected, body
    assert expected.positive?, "pack must put spend on the open bill for this assertion to bite"
  end

  # WA-QRY-03
  test "como tá o mês: every MonthSummary term is exact" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    summary = MonthSummary.new(s.account, Date.current.beginning_of_month)

    ask_query(s, nil, "como tá o mês?")   # query_kind nil → month answer

    body = assert_wa_reply(s.jid)
    assert_brl summary.incomes_cents, body
    assert_brl summary.expenses_cents, body
    assert_brl summary.remaining_cents, body
    # The pack's terms are themselves frozen: income received this month is the salary.
    assert_equal 500_000, summary.incomes_cents
  end

  # WA-QRY-04
  test "quanto já guardei: savings total and this month's stash" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!

    ask_query(s, "savings_total", "quanto já guardei?")

    body = assert_wa_reply(s.jid)
    assert_brl 30_000, body, "this month's guardado is the pack's fixed stash"
  end

  # WA-QRY-05
  test "a query on an empty account answers gracefully" do
    s = E2E::Scenario.build(:bare).wa_verified!

    ask_query(s, "account_balance", "quanto tenho?")

    body = assert_wa_reply(s.jid)
    assert_brl 0, body
    assert_empty s.account.transactions, "queries never write"
  end

  private

  def ask_query(s, kind, text)
    with_canned_ai(extraction: E2E::CannedAI.query(kind)) do
      wa_inject(s.jid, text)
      drain_jobs!
    end
  end
end
