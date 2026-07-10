require "test_helpers/e2e/pipeline_case"

# Web tenancy / redirect guards (.plans/e2e/05 §2/§3). Lane P: forged cross-account foreign
# keys must be sanitized to nil (no cross-tenant write), and the card return_to token must
# only ever redirect within the app.
class E2E::WebTenancyGuardsTest < E2E::PipelineCase
  # WEB-TX-04 — a POSTed category_id belonging to ANOTHER account is sanitized to nil; the row
  # posts uncategorized rather than pointing across the tenant boundary.
  test "a forged cross-account category_id is sanitized to nil on create" do
    s        = E2E::Scenario.build(:solo_basic)
    stranger = E2E::Scenario.build(:solo_basic)
    foreign  = stranger.category("Mercado")

    sign_in_as s.owner
    assert_difference -> { s.account.transactions.count }, 1 do
      post transactions_path, params: { transaction: {
        amount_reais: "50,00", merchant: "Feira", occurred_on: Date.current.to_s,
        category_id: foreign.id, payment_method: "debito" } }
    end
    txn = s.account.transactions.order(:created_at).last
    assert_nil txn.category_id, "the foreign category_id was dropped, not written"
    assert_not stranger.account.transactions.exists?(id: txn.id), "no cross-tenant write"
  end

  # WEB-CARD-04 — the card edit return_to token only honors the literal "transactions"; anything
  # else (a URL, a foreign host) falls back to the cards page — no open-redirect surface.
  test "the card return_to token only redirects within the app" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner

    patch credit_card_path(s.nubank_card),
          params: { credit_card: { nickname: "Roxinho" }, return_to: "transactions" }
    assert_redirected_to transactions_path(month: nil)

    patch credit_card_path(s.nubank_card),
          params: { credit_card: { nickname: "Roxinho" }, return_to: "https://evil.example.com" }
    assert_redirected_to credit_cards_path, "a non-'transactions' return_to falls back to the cards page"
  end
end
