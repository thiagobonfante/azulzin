require "test_helpers/e2e/pipeline_case"

# WEB-REC-01/02/04 (.plans/e2e/05 §10): the "Hoje" purchase-date view. The money contract:
# gastos de um dia = Σ expense rows, split débito (no card) + faturas (card) to the exact
# centavo; transfers count into neither figure; incomes only into the entradas caption. Card
# swipes made today are today's spending even though they settle on next month's fatura —
# the badge says so. Under the May-20 anchor, "next month's fatura" reads "fatura de junho".
class E2E::WebRecentViewTest < E2E::PipelineCase
  # WEB-REC-01 — the founder example: PIX R$ 100 + 2× card R$ 50 today (card due 10 /
  # closes the 3rd) ⇒ Gastos de hoje R$ 200,00, split R$ 100,00 / R$ 100,00, both card
  # rows badged with the future fatura.
  test "today's spend counts PIX and card together and badges the future fatura" do
    s = E2E::Scenario.build(:recent_days)
    sign_in_as s.owner

    get recent_transactions_path
    assert_response :success

    assert_includes response.body, "Gastos de hoje"
    assert_brl 20_000, response.body                            # 10_000 débito + 10_000 faturas
    assert_includes response.body, "R$ 100,00 no débito"
    assert_includes response.body, "R$ 100,00 nas faturas"
    assert_select "span.badge-outline", text: /fatura de junho/, count: 2

    assert_includes response.body, "Gastos de ontem"
    assert_brl 8_490, response.body
  end

  # WEB-REC-02 — day separation, recents-first ordering inside a day, and incomes/transfers
  # in the list but out of gastos.
  test "days separate, recents render first, incomes and transfers stay out of gastos" do
    s = E2E::Scenario.build(:recent_days)
    s.add_caixinha!
    s.stash(30_000, on: Date.current)   # transfer: visible, in NO figure
    s.account.transactions.create!(
      merchant: "Reembolso", direction: "income", status: "posted", source: "manual",
      amount_cents: 7_700, occurred_on: Date.current, confirmed_at: Time.current,
      bank_account: s.itau, created_by: s.owner)
    sign_in_as s.owner

    get recent_transactions_path
    assert_response :success

    # Gastos unchanged by the R$ 300,00 transfer and R$ 77,00 income (still 100/100 = 200).
    assert_includes response.body, "R$ 100,00 no débito"
    assert_includes response.body, "R$ 100,00 nas faturas"
    assert_includes response.body, "+R$ 77,00 de entradas"
    assert_includes response.body, "Caixinha", "the transfer row renders in the day list"

    # Today's section precedes yesterday's; within today, most recently captured first
    # (the income/transfer were created at 12:00, the pack rows at midnight; among the pack
    # rows the tie breaks by id, so Uber — captured last — precedes Pix Farmácia).
    body = response.body
    assert_operator body.index("Gastos de hoje"), :<, body.index("Gastos de ontem")
    assert_operator body.index("Reembolso"), :<, body.index("Uber")
    assert_operator body.index("Uber"), :<, body.index("Pix Farmácia")
    assert_operator body.index("Pix Farmácia"), :<, body.index("Supermercado Zaffari")
  end

  # WEB-REC-04 — the three empty states: dashed capture CTA when both days are empty, quiet
  # per-day lines otherwise, and never a fake R$ 0,00 figure (founder call #3).
  test "empty states render quiet lines, never fake zero totals" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner

    get recent_transactions_path
    assert_response :success
    assert_includes response.body, "Nenhum movimento por aqui ainda"
    assert_includes response.body, "Mande um áudio no WhatsApp que a gente lança pra você"
    refute_includes response.body, "Gastos de hoje"
    refute_includes response.body, "R$ 0,00"

    # Yesterday only → quiet today line + yesterday figures.
    yesterday_row = s.expense(merchant: "Mercadinho Ontem", category: "Mercado",
                              instrument: s.itau, cents: 8_490, on: Date.current - 1)
    get recent_transactions_path
    assert_includes response.body, "Nenhum movimento hoje ainda"
    assert_includes response.body, "Gastos de ontem"
    assert_brl 8_490, response.body
    refute_includes response.body, "Nenhum movimento por aqui ainda"

    # Today only → quiet yesterday line, no zero total for it.
    yesterday_row.soft_delete!(by: s.owner)
    s.expense(merchant: "Café Hoje", category: "Restaurantes", instrument: s.itau,
              cents: 1_200, on: Date.current)
    get recent_transactions_path
    assert_includes response.body, "Nenhum movimento ontem"
    assert_includes response.body, "Gastos de hoje"
    assert_brl 1_200, response.body
    refute_includes response.body, "R$ 0,00"
  end

  # Hub regression for the shared-partial badge (.plans/today-expenses §5): same-month card
  # rows — the vast majority of any month ledger — stay badge-free; the June page's May-dated
  # purchases now explain themselves.
  test "hub ledger: no badge on same-month card rows, badge on cross-month ones" do
    s = E2E::Scenario.build(:recent_days)
    # Before the closing day (the 3rd) a purchase bills into its own month → no badge.
    s.expense(merchant: "Compra Cedo", category: "Outros", instrument: s.nubank_card,
              cents: 3_300, on: Date.current.beginning_of_month + 1)
    sign_in_as s.owner

    get transactions_path
    assert_response :success
    assert_includes response.body, "Compra Cedo"
    assert_select "span.badge-outline", text: /fatura de/, count: 0

    get transactions_path(month: (Date.current.beginning_of_month >> 1).strftime("%Y-%m"))
    assert_response :success
    assert_includes response.body, "Padoca"   # bought May 20, billed June
    assert_select "span.badge-outline", text: /fatura de junho/, count: 2
  end
end
