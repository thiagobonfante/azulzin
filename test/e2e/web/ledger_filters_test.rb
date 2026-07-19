require "test_helpers/e2e/pipeline_case"

# WEB-TX-12: payment-method differentiation on the hub ledger — every expense row wears its
# forma de pagamento as a tag, and ?method= narrows the list (whitelisted; garbage → all).
class E2E::WebLedgerFiltersTest < E2E::PipelineCase
  test "rows show their payment method and ?method= filters the ledger" do
    s = E2E::Scenario.build(:solo_basic)
    s.expense(merchant: "Farmácia Pix",  category: "Saúde",   instrument: s.itau, cents: 1_000,
              on: Date.current, method: "pix")
    s.expense(merchant: "Conta Boleto",  category: "Contas",  instrument: s.itau, cents: 500,
              on: Date.current, method: "boleto")
    s.expense(merchant: "Loja Cartão",   category: "Outros",  instrument: s.nubank_card, cents: 2_000,
              on: Date.current.beginning_of_month + 1, method: "credito")
    sign_in_as s.owner

    get transactions_path
    assert_response :success
    assert_select "span.badge-ghost", text: "Pix",    count: 1
    assert_select "span.badge-ghost", text: "Boleto", count: 1

    # Scoped to the list — the bills tile legitimately names card purchases elsewhere.
    get transactions_path(method: "pix")
    list = css_select("#ledger_list").text
    assert_includes list, "Farmácia Pix"
    refute_includes list, "Conta Boleto"
    refute_includes list, "Loja Cartão"
    assert_brl 1_000, list

    # Garbage method falls back to all.
    get transactions_path(method: "cheque")
    list = css_select("#ledger_list").text
    assert_includes list, "Farmácia Pix"
    assert_includes list, "Conta Boleto"
    assert_includes list, "Loja Cartão"
  end
end
