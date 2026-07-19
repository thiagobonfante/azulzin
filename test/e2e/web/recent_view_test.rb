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
    # 2 badged card rows × the responsive pair (caption badge on <sm, inline badge on sm+).
    assert_select "span.badge-outline", text: /fatura de junho/, count: 4

    assert_includes response.body, "Gastos de ontem"
    assert_brl 8_490, response.body

    # Search-by-value material: the formatted amount is baked into each row's data-search
    # (the client-side box matches "100" or "100,00"; lowercased, so unique to the attr).
    assert_includes response.body, "r$ 100,00"
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

  # WEB-REC-03 — category chips: a chip filters the day lists AND recomputes the totals to
  # the centavo; chips derive from the unfiltered window (escape stays visible); garbage
  # falls back to all; Todas resets.
  test "category chips filter rows and recompute totals; garbage falls back to all" do
    s = E2E::Scenario.build(:recent_days)
    uncat = s.expense(merchant: "Banca de Jornal", category: "Outros", instrument: s.itau,
                      cents: 750, on: Date.current)
    uncat.update!(category_id: nil, category_source: nil)
    sign_in_as s.owner

    # Restaurantes = only Padoca (card, R$ 50,00): all-card split, yesterday goes quiet.
    get recent_transactions_path(category: s.category("Restaurantes").id)
    assert_response :success
    assert_includes response.body, "Padoca"
    refute_includes response.body, "Pix Farmácia"
    refute_includes response.body, "Supermercado Zaffari"
    assert_includes response.body, "R$ 0,00 no débito"
    assert_includes response.body, "R$ 50,00 nas faturas"
    assert_includes response.body, "Nenhum movimento ontem"
    assert_includes response.body, "Mercado", "chips derive from the unfiltered window"

    # Sem categoria: only the uncategorized expense counts.
    get recent_transactions_path(category: "none")
    assert_includes response.body, "Banca de Jornal"
    refute_includes response.body, "Padoca"
    assert_includes response.body, "Gastos de hoje"
    assert_brl 750, response.body

    # Garbage id → all rows, full totals (Todas is this same unfiltered render).
    get recent_transactions_path(category: "999999")
    assert_includes response.body, "R$ 100,00 nas faturas"
    assert_brl 20_750, response.body   # 20_000 + the R$ 7,50 uncategorized row
  end

  # WEB-REC-05 — totals freshness: drawer edits carrying context=recent stream a fresh
  # recent_summary (figures + day lists from a re-loaded window, chip filter preserved);
  # a row edited out of the two-day window disappears; hub edits stream nothing extra.
  test "recent-context edits stream fresh figures; hub edits don't" do
    s = E2E::Scenario.build(:recent_days)
    sign_in_as s.owner
    padoca = s.account.transactions.find_by!(merchant: "Padoca")
    pix    = s.account.transactions.find_by!(merchant: "Pix Farmácia")
    uber   = s.account.transactions.find_by!(merchant: "Uber")

    # The page's row links thread the context; the edit form carries it as a hidden field —
    # the PATCHes below travel exactly what the drawer would submit.
    get recent_transactions_path
    assert_includes response.body, "context=recent"
    get edit_transaction_path(padoca, context: "recent")
    assert_includes response.body, 'name="context"'

    # Amount edit under the Restaurantes chip: fresh sections keep the filter — only Padoca,
    # at its new amount (R$ 50,00 → R$ 75,00, all on the fatura).
    patch transaction_path(padoca), as: :turbo_stream,
          params: { from: "ledger", context: "recent", category: s.category("Restaurantes").id,
                    transaction: { amount_reais: "75,00" } }
    assert_response :success
    assert_includes response.body, 'target="recent_summary"'
    assert_includes response.body, "R$ 0,00 no débito"
    assert_includes response.body, "R$ 75,00 nas faturas"
    refute_includes response.body, "Pix Farmácia"

    # Destroy from the drawer: figures drop the deleted row (unfiltered: 75 + 50 card only).
    delete transaction_path(pix), as: :turbo_stream, params: { from: "ledger", context: "recent" }
    assert_response :success
    assert_includes response.body, 'target="recent_summary"'
    assert_includes response.body, "R$ 0,00 no débito"
    assert_includes response.body, "R$ 125,00 nas faturas"

    # The chip row streams too: deleting the last uncategorized row retires its chip live.
    uncat = s.expense(merchant: "Banca", category: "Outros", instrument: s.itau,
                      cents: 750, on: Date.current)
    uncat.update!(category_id: nil, category_source: nil)
    delete transaction_path(uncat), as: :turbo_stream, params: { from: "ledger", context: "recent" }
    assert_response :success
    chips = response.body[/<turbo-stream[^>]*target="recent_chips".*?<\/turbo-stream>/m]
    assert chips, "the destroy stream must refresh the chip row"
    refute_includes chips, "Sem categoria"

    # occurred_on moved out of the two-day window: the fresh sections no longer carry the row
    # (the hub-shaped row op may still mention it — the sections replace renders last and wins).
    patch transaction_path(uber), as: :turbo_stream,
          params: { from: "ledger", context: "recent",
                    transaction: { occurred_on: Date.current - 10 } }
    assert_response :success
    sections = response.body[/<turbo-stream[^>]*target="recent_summary".*?<\/turbo-stream>/m]
    assert sections, "the update stream must refresh the day sections"
    refute_includes sections, "Uber"
    assert_includes sections, "R$ 75,00 nas faturas"

    # A hub edit (no context param) must not stream the recent block.
    patch transaction_path(padoca), as: :turbo_stream,
          params: { from: "ledger", transaction: { amount_reais: "80,00" } }
    assert_response :success
    refute_includes response.body, 'target="recent_summary"'
  end

  # WEB-REC-07 — adding from the Recentes page: the new-entry form threads context=recent and
  # the create stream lands the new row in the day list with fresh figures.
  test "adding a transaction from Recentes streams it into the day list" do
    s = E2E::Scenario.build(:recent_days)
    sign_in_as s.owner

    get new_transaction_path(kind: :expense, context: "recent")
    assert_response :success
    assert_includes response.body, "context=recent", "the form must carry the context through"

    post transactions_path(kind: "expense", context: "recent"), as: :turbo_stream,
         params: { instrument: "bank_account-#{s.itau.id}",
                   transaction: { amount_reais: "12,00", merchant: "Café Novo",
                                  occurred_on: Date.current, payment_method: "pix" } }
    assert_response :success
    sections = response.body[/<turbo-stream[^>]*target="recent_summary".*?<\/turbo-stream>/m]
    assert sections, "the create stream must refresh the day sections"
    assert_includes sections, "Café Novo"
    assert_includes sections, "R$ 112,00 no débito"   # 10_000 + the new 1_200
  end

  # WEB-REC-06 — the dashboard's "Gastos de hoje" tile: the exact figure the Hoje page
  # shows (purchase-date sum, yesterday excluded), linking there.
  test "dashboard tile shows today's spend, equal to the page figure" do
    s = E2E::Scenario.build(:recent_days)
    sign_in_as s.owner

    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", recent_transactions_path, text: /Gastos de hoje/
    assert_select "a[href=?]", recent_transactions_path, text: /R\$ 200,00/   # 20_000: today only
  end

  # WEB-TX-13 — the hub purchase-date union + view-relative badge (founder call 2026-07-19):
  # a card swipe made this month but billed next month shows on THIS month's page, badged with
  # where it bills; the next month's page lists it unbadged (billing == viewed month there).
  test "hub ledger: this month's future-billed card buys show here badged, unbadged on their bill month" do
    s = E2E::Scenario.build(:recent_days)
    # Before the closing day (the 3rd) a purchase bills into its own month → listed, no badge.
    s.expense(merchant: "Compra Cedo", category: "Outros", instrument: s.nubank_card,
              cents: 3_300, on: Date.current.beginning_of_month + 1)
    sign_in_as s.owner
    padoca = s.account.transactions.find_by!(merchant: "Padoca")

    get transactions_path   # May: Padoca + Uber (bought May 20, billed June) join via the union
    assert_response :success
    assert_includes response.body, "Compra Cedo"
    assert_includes response.body, "Padoca"
    assert_select "span.badge-outline", text: /fatura de junho/, count: 4   # 2 rows × responsive pair

    get transactions_path(month: (Date.current.beginning_of_month >> 1).strftime("%Y-%m"))
    assert_response :success
    assert_includes response.body, "Padoca"   # on its bill month: listed, nothing to flag
    assert_select "span.badge-outline", text: /fatura de/, count: 0

    # Editing a union row from May's ledger must REPLACE it, not remove it as foreign.
    patch transaction_path(padoca), as: :turbo_stream,
          params: { from: "ledger", month: Date.current.strftime("%Y-%m"),
                    transaction: { merchant: "Padoca da Esquina" } }
    assert_response :success
    assert_includes response.body, %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(padoca, :row)}")
  end
end
