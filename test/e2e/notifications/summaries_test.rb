require "test_helpers/e2e/pipeline_case"

# NT-S: weekly/monthly digests through the real dispatch jobs (.plans/e2e/04 §3).
class E2E::NotificationSummariesTest < E2E::PipelineCase
  SUNDAY_8PM_SP = Time.utc(2026, 5, 24, 23, 0)
  FIRST_8AM_SP  = Time.utc(2026, 6, 1, 11, 0)

  # NT-S-01
  test "weekly summary: exact digest body" do
    travel_to SUNDAY_8PM_SP
    s = push_ready(E2E::Scenario.build(:history_calibrated), :weekly_summary)

    Summaries::WeeklyDispatchJob.perform_now
    drain_jobs!

    assert_wa_reply s.jid, equals: <<~GOLDEN.strip
      📊 *Resumo da semana*
      Você gastou R$ 2.612,79 — Mercado R$ 1.325,00, Restaurantes R$ 647,80, Transporte R$ 360,00, outros R$ 279,99.
      Sobra do mês até agora: R$ 2.087,21.
      💙
    GOLDEN
  end

  # NT-S-02
  test "monthly summary: recaps the JUST-CLOSED month exactly" do
    travel_to FIRST_8AM_SP
    s = push_ready(E2E::Scenario.build(:history_calibrated), :monthly_summary)

    Summaries::MonthlyDispatchJob.perform_now
    drain_jobs!

    # May in the pack is deliberately red (the Vestuário R$ 4.100,00 median-buster) — the
    # recap must state it plainly, negative sobra and all.
    assert_wa_reply s.jid, equals: <<~GOLDEN.strip
      📅 *Maio fechou*
      Entrou R$ 5.000,00, saiu R$ 6.100,00, faturas R$ 0,00.
      Sobra do mês: -R$ 1.400,00 · guardado: R$ 300,00.
      Você ficou dentro do combinado em 4 de 4 categorias.
      💙
    GOLDEN
  end

  # NT-S-03 — nothing to say ⇒ no row at all
  test "an empty account gets no summary row" do
    travel_to SUNDAY_8PM_SP
    s = push_ready(E2E::Scenario.build(:bare), :weekly_summary)

    Summaries::WeeklyDispatchJob.perform_now
    drain_jobs!

    assert_not Notification.exists?(user: s.owner, kind: "weekly_summary"),
               "no digest row when there is nothing to say"
    assert_no_wa_reply s.jid
  end

  # NT-S-04 — the toggle is checked in the JOB: no dashboard surprise either
  test "toggle off means no summary row, not just no push" do
    travel_to SUNDAY_8PM_SP
    s = push_ready(E2E::Scenario.build(:history_calibrated), :weekly_summary)
    s.owner.notification_prefs.update!(weekly_summary: false)

    Summaries::WeeklyDispatchJob.perform_now
    drain_jobs!

    assert_not Notification.exists?(user: s.owner, kind: "weekly_summary")
  end

  private

  def push_ready(s, toggle)
    s.wa_verified!(consent: true)
    s.owner.notification_prefs.update!(wa_intro_sent_at: Time.current, toggle => true)
    wa_connect!
    s
  end
end
