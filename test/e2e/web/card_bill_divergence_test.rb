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

    # While pending: the bill page shows OUR figure + the warning (never the bank's
    # number), Pagar is disabled, and the amounts live on the review page only.
    assert bill.divergence_pending?
    assert_equal 125_000, bill.effective_total_cents, "the bank's number never leaks mid-check"
    get card_bill_url(bill)
    assert_includes response.body, I18n.t("card_bills.review.pending_warning", locale: :"pt-BR")
    assert_select "button[data-action='modal#open'][disabled]", text: I18n.t("card_bills.show.pay", locale: :"pt-BR")

    get review_card_bill_url(bill)
    assert_includes response.body,
                    I18n.t("card_bills.divergence.ours_higher", amount: brl(15_000), locale: :"pt-BR")
    assert_not_includes response.body, "Mercado Grande", "picker offers only closing-edge rows"

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

  test "BILL-05: bank higher than us → inverse copy on the review page, no picker" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    patch card_bill_url(bill), params: { stated_total_reais: "1.400,00" }

    get review_card_bill_url(bill)
    assert_includes response.body,
                    I18n.t("card_bills.divergence.bank_higher", amount: brl(15_000), locale: :"pt-BR")
    assert_not_includes response.body, I18n.t("card_bills.divergence.picker_title", locale: :"pt-BR")
  end

  # The missed-purchase form (founder round 2026-07-22b): a normal card expense, its date
  # CLAMPED to this bill's window, pinned to this bill.
  test "add_line records the found purchase clamped to the bill window" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill
    patch card_bill_url(bill), params: { stated_total_reais: "1.400,00" }

    post add_line_card_bill_url(bill), params: {
      merchant: "Compra Esquecida", amount_reais: "150,00", occurred_on: Date.current.iso8601 }

    line = s.account.transactions.find_by!(merchant: "Compra Esquecida")
    assert_equal 15_000, line.amount_cents
    assert_equal bill.closed_on, line.occurred_on, "today is past closing — clamped to the closing date"
    assert_equal bill.billing_month, line.billing_month
    assert line.billing_month_manual?
    assert_equal 140_000, bill.reload.computed_total_cents
    assert_not bill.divergence_pending?, "the found purchase closes the check"
  end

  # Founder round 2026-07-22: resolution lives on the FOCUSED review page — a diverging
  # inform redirects there; the delta can be recorded as a DELETABLE adjustment row
  # (deleting it is the rollback); cancel forgets the informed value.
  test "review page: divergent inform lands there; adjust writes the delta row; cancel clears" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    patch card_bill_url(bill), params: { stated_total_reais: "1.100,00" }
    assert_redirected_to review_card_bill_url(bill)
    get review_card_bill_url(bill)
    assert_includes response.body, I18n.t("card_bills.divergence.picker_title", locale: :"pt-BR")
    assert_includes response.body, I18n.t("card_bills.review.cancel_cta", locale: :"pt-BR")

    # ours 1.250,00 > bank 1.100,00 → the adjustment is a −R$ 150,00 credit on the card.
    post adjust_card_bill_url(bill)
    adjustment = s.account.transactions.order(:id).last
    assert adjustment.income?, "ours-higher adjusts DOWN via a credit row"
    assert_equal 15_000, adjustment.amount_cents
    assert_equal bill.billing_month, adjustment.billing_month
    assert adjustment.billing_month_manual?, "the adjustment never re-buckets"
    assert_equal 110_000, bill.reload.computed_total_cents, "computed now matches the bank"

    adjustment.soft_delete!(by: s.owner)   # the promised rollback
    assert_equal 125_000, bill.reload.computed_total_cents

    patch clear_stated_card_bill_url(bill)
    assert_nil bill.reload.stated_total_cents, "cancel forgets the bank value"
  end

  # A matching inform never opens the resolution page; bank-higher adjusts UP (expense).
  test "matching inform stays on the bill page; bank-higher adjust adds an expense" do
    s = E2E::Scenario.build(:bill_closed)
    sign_in_as s.owner
    bill = s.closed_bill

    patch card_bill_url(bill), params: { stated_total_reais: "1.250,00" }
    assert_redirected_to card_bill_url(bill)

    patch card_bill_url(bill), params: { stated_total_reais: "1.400,00" }
    assert_redirected_to review_card_bill_url(bill)
    post adjust_card_bill_url(bill)
    adjustment = s.account.transactions.order(:id).last
    assert adjustment.expense?, "bank-higher adjusts UP via an expense row"
    assert_equal 15_000, adjustment.amount_cents
    assert_equal 140_000, bill.reload.computed_total_cents
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
