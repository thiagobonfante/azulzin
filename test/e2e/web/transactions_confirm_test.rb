require "test_helpers/e2e/pipeline_case"

# WEB-TX-09: the double-submit guard on confirm (.plans/e2e-t3 §C). A WA-parked expense
# confirmed twice from the tray must post exactly once — guarded_update only moves a row
# still in a pending status, so the second POST is a no-op: no second ledger row, no
# re-applied confirm. (HYB-02 owns the happy tray-confirm journey; this is the race guard.)
class E2E::WebTransactionsConfirmTest < E2E::PipelineCase
  test "a parked WA row confirmed twice posts exactly once" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 3_000, merchant: "uns trecos",
                                                     confidence: 0.4, amount_confidence: 0.4)) do
      wa_inject(s.jid, "acho que gastei uns 30")
      drain_jobs!
    end
    txn = s.account.transactions.sole
    assert txn.pending_review?

    sign_in_as s.owner
    month = txn.billing_month.strftime("%Y-%m")
    patch confirm_transaction_path(txn), params: { month: month }, as: :turbo_stream
    assert_response :success
    assert txn.reload.posted?
    first_confirmed_at = txn.confirmed_at

    travel 1.hour   # make a re-applied confirm observable under frozen time
    patch confirm_transaction_path(txn), params: { month: month }, as: :turbo_stream
    assert_response :success
    assert_equal 1, s.account.transactions.count, "no second ledger row"
    txn.reload
    assert txn.posted?
    assert_equal first_confirmed_at, txn.confirmed_at, "the second confirm must not re-apply"
  end
end
