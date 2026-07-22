require "test_helpers/e2e/pipeline_case"

# BILL-05 — divergence (.plans/credit-cards 03 §1): computed 125.000¢ vs stated 110.000¢,
# the closing-edge purchase (15.000¢) is the culprit; picking it re-buckets it forward via
# the sticky manual move, the banner flips to "bate com o banco", and no later config
# edit ever re-buckets the moved row.
class E2E::WebCardBillDivergenceTest < E2E::PipelineCase
  test "BILL-05: inform stated → banner shows the difference → pick the edge purchase → bate com o banco" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    patch card_bill_url(bill), params: { stated_total_reais: "1.100,00" }
    assert_equal 110_000, bill.reload.stated_total_cents

    get card_bill_url(bill)
    assert_includes response.body,
                    I18n.t("card_bills.divergence.ours_higher", amount: brl(15_000), locale: :"pt-BR")

    edge = s.account.transactions.find_by!(merchant: "Na Borda do Corte")
    patch carry_over_card_bill_url(bill), params: { transaction_ids: [ edge.id ] }

    edge.reload
    assert_equal bill.billing_month >> 1, edge.billing_month, "moved to the NEXT fatura"
    assert edge.billing_month_manual?, "the move is the sticky manual move"
    assert_equal 110_000, bill.reload.computed_total_cents, "computed now matches the bank"

    get card_bill_url(bill)
    assert_includes response.body, I18n.t("card_bills.divergence.matches", locale: :"pt-BR")

    # A later card-config edit must NOT re-bucket the moved row (manual is sticky).
    s.nubank_card.update!(closing_offset_days: 5)
    s.nubank_card.recompute_billing_months!(first_time: false)
    assert_equal bill.billing_month >> 1, edge.reload.billing_month
  end

  test "BILL-05: bank higher than us → inverse copy, no picker" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    patch card_bill_url(bill), params: { stated_total_reais: "1.400,00" }

    get card_bill_url(bill)
    assert_includes response.body,
                    I18n.t("card_bills.divergence.bank_higher", amount: brl(15_000), locale: :"pt-BR")
    assert_not_includes response.body, I18n.t("card_bills.divergence.picker_title", locale: :"pt-BR")
  end

  # A bill with a posted parcel: the picker moves ONLY the picked parcel — the plan's
  # other months and the commitment itself stay untouched (per-parcel semantics).
  test "picker on a bill with parcels moves only the picked parcel" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill
    commitment = Installments::Create.call(
      account: s.account, created_by: s.owner, card: s.nubank_card,
      total_cents: 30_000, count: 3, occurred_on: bill.closed_on - 1, merchant: "Parcelada Edge")
    parcel = Commitments::MarkPaid.call(commitment, bill.billing_month)
    assert_equal bill.billing_month, parcel.billing_month

    patch carry_over_card_bill_url(bill), params: { transaction_ids: [ parcel.id ] }

    assert_equal bill.billing_month >> 1, parcel.reload.billing_month
    assert_equal 3, commitment.reload.installments_count
    assert_equal 1, commitment.payments.posted.kept.count, "only the one posted parcel exists — siblings stay projections"
  end
end
