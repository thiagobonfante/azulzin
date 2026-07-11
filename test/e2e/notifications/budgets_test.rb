require "test_helpers/e2e/pipeline_case"

# NT-B: budget bands through the REAL weekly check, to the centavo (.plans/e2e/04 §3).
# The pack calibrates: Mercado 88,3% · Restaurantes 108% · Transporte exactly 80% ·
# Lazer 79,997%. Weekly checks dispatch on Mondays — tests travel to the anchor's Monday.
class E2E::NotificationBudgetsTest < E2E::PipelineCase
  MONDAY = Time.utc(2026, 5, 18, 15, 0)   # anchor week's Monday, 12:00 SP

  # NT-B-01/02/03 — the three goldens and the one-cent-under silence, in one sweep
  test "flat bands: two warns, one breach, silence one centavo under" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:history_calibrated))

    dispatch_budgets!

    bodies = fake_sidecar.messages_to(s.jid).map(&:body)
    assert_includes bodies, "👀 *Mercado* já está em R$ 1.325,00 de R$ 1.500,00 este mês. Faltam R$ 175,00."
    assert_includes bodies, "⚠️ *Restaurantes* passou do combinado: R$ 647,80 de R$ 600,00 este mês."
    assert_includes bodies, "👀 *Transporte* já está em R$ 360,00 de R$ 450,00 este mês. Faltam R$ 90,00."
    assert bodies.none? { |b| b.include?("Lazer") }, "79,997% must stay silent"
    assert_not Notification.exists?(user: s.owner, kind: %w[budget_warn budget_breach],
                                    subject: s.category("Lazer"))
  end

  # NT-B-04 — the member's own bands, not the defaults
  test "custom bands move the boundary: warn 60 catches Lazer" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:history_calibrated))
    s.owner.notification_prefs.update!(budget_warn_percent: 60, budget_breach_percent: 90)

    dispatch_budgets!

    lazer = Notification.where(user: s.owner, kind: "budget_warn", subject: s.category("Lazer")).sole
    assert_equal 27_999, lazer.payload["spent_cents"]
    assert Notification.exists?(user: s.owner, kind: "budget_breach", subject: s.category("Restaurantes"))
  end

  # NT-B-05 — a goal trim binds tighter than the standing budget: the _goal copy names the
  # meta and the effective limit is min(standing, trim). Spec 04 §NT-B-05.
  test "goal trim binds tighter than the standing budget: budget_warn_goal names the meta" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:goal_cuts))

    dispatch_budgets!

    assert_wa_reply s.jid,
      equals: "👀 *Restaurantes* já está em R$ 340,00 do combinado da meta *Carro* este mês (R$ 400,00). 💙"
    n = Notification.where(user: s.owner, kind: "budget_warn", subject: s.category("Restaurantes")).sole
    assert_equal 40_000, n.payload["budget_cents"], "effective_limit = min(60_000 standing, 40_000 trim)"
    assert_equal "Carro", n.payload["goal_name"]
  end

  # NT-B-06 — surplus nudge only in the last week, only in the blue, exact sobra
  test "surplus nudge: last week of the month banks the exact sobra" do
    travel_to Time.utc(2026, 5, 25, 15, 0)   # last Monday of May
    s = push_ready(E2E::Scenario.build(:history_calibrated))
    clear_band_budgets(s)

    dispatch_budgets!

    assert_wa_reply s.jid,
      equals: "💙 Você fechou o mês com *R$ 2.087,21* de sobra. Quer guardar esse dindin?"
  end

  # 2026-07-11: no poupança but an investment account → the nudge names it instead
  test "surplus nudge names the investment account when there's no poupança" do
    travel_to Time.utc(2026, 5, 25, 15, 0)
    s = push_ready(E2E::Scenario.build(:history_calibrated))
    clear_band_budgets(s)
    s.account.bank_accounts.kept.savings.update_all(kind: "investment")

    dispatch_budgets!

    assert_wa_reply s.jid,
      # sobra is R$ 300,00 higher than the base golden: the flipped account's transfers no
      # longer count as guardado (guardado is savings-kind only), so they ride the sobra.
      equals: "💙 Você fechou o mês com *R$ 2.387,21* de sobra. Quer mandar pra sua conta investimento?"
  end

  test "surplus nudge stays silent mid-month" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:history_calibrated))
    clear_band_budgets(s)

    dispatch_budgets!

    assert_no_wa_reply s.jid
    assert_not Notification.exists?(user: s.owner, kind: %w[surplus_nudge rightsize_budget])
  end

  # NT-B-07 — rightsize the one budget lying hardest (median from the pack's 400/420/4.100 triple)
  test "rightsize: budget at 238% of the median gets the tidy-up copy" do
    travel_to Time.utc(2026, 5, 25, 15, 0)
    s = push_ready(E2E::Scenario.build(:history_calibrated))
    clear_band_budgets(s)
    s.category("Vestuário").update!(monthly_budget_cents: 100_000)
    # Push the sobra under the R$ 50,00 floor (still in the blue) so rightsize gets its turn.
    s.expense(merchant: "Reforma", category: "Moradia", instrument: s.itau,
              cents: 204_721, on: Date.current - 1)

    dispatch_budgets!

    assert_wa_reply s.jid,
      equals: "💙 *Vestuário*: você combinou R$ 1.000,00, mas costuma gastar R$ 420,00. Dá pra ajustar em Categorias."
  end

  # NT-B-08 — the same Monday re-run is a no-op
  test "re-dispatching the same week sends nothing new" do
    travel_to MONDAY
    s = push_ready(E2E::Scenario.build(:history_calibrated))

    dispatch_budgets!
    first = fake_sidecar.messages_to(s.jid).size
    assert_operator first, :>, 0

    dispatch_budgets!
    assert_equal first, fake_sidecar.messages_to(s.jid).size
  end

  private

  def push_ready(s)
    s.wa_verified!(consent: true)
    s.owner.notification_prefs.update!(wa_intro_sent_at: Time.current)
    wa_connect!
    s
  end

  def clear_band_budgets(s)
    %w[Mercado Restaurantes Transporte Lazer].each do |name|
      s.category(name).update!(monthly_budget_cents: nil)
    end
  end

  def dispatch_budgets!
    Budgets::WeeklyCheckDispatchJob.perform_now
    drain_jobs!
  end
end
