require "test_helpers/e2e/pipeline_case"

# WA-GOAL: the goal-creation chat — conversational Q&A → real draft → accept → ACTIVE goal
# with its pay-yourself-first commitment (.plans/e2e/03 §4). Replies after the trigger are
# routed zero-LLM by GoalFlowRouter, so only the trigger needs canned AI.
class E2E::WhatsappGoalsChatTest < E2E::PipelineCase
  # WA-GOAL-01 — the full happy path, every slot answered by text
  test "full chat: kind → name → amount → month → initial → offer → sim → ACTIVE goal + commitment" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!

    start_goal_chat(s, "quero criar uma meta")
    say s, "1"            # kind: purchase
    say s, "Carro novo"   # name
    say s, "20.000"       # target
    say s, "dezembro"     # target month (parsed relative to the frozen anchor)
    say s, "2.000"        # initial saved

    goal = s.account.goals.sole
    assert goal.draft?
    assert_equal 2_000_000, goal.target_cents
    assert_equal 200_000, goal.initial_saved_cents
    assert_equal "purchase", goal.kind
    assert_equal "Carro novo", goal.name
    offer = assert_wa_reply(s.jid)
    assert_includes offer, goal.name

    say s, "sim"          # accept → single caixinha + single source resolve automatically

    goal.reload
    assert goal.active?, "sim on the offer must activate the goal"
    assert_equal s.caixinha.id, goal.bank_account_id, "the goal links its caixinha"
    commitment = s.account.commitments.where(kind: "savings").sole
    assert_equal goal, commitment.goal
    assert_equal s.itau, commitment.bank_account, "the commitment debits the source account"
    assert_not GoalConversation.open_for(s.owner), "the conversation must close on activation"
  end

  # WA-GOAL-02 — não at the offer discards the invisible draft
  test "declining the offer destroys the draft" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    walk_to_offer(s)
    assert_equal 1, s.account.goals.count

    say s, "não"

    assert_empty s.account.goals.reload, "a declined draft must not linger (quota hygiene)"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.goal_flow.discarded", locale: :"pt-BR"))
    assert_not GoalConversation.open_for(s.owner)
  end

  # WA-GOAL-02b — cancelar works mid-collection too
  test "cancelar mid-flow closes the conversation" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    start_goal_chat(s, "quero criar uma meta")
    say s, "1"

    say s, "cancelar"

    assert_not GoalConversation.open_for(s.owner)
    assert_empty s.account.goals, "no draft exists yet at the name slot"
  end

  # WA-GOAL-03 — 24h TTL: the chat expires passively; the next message starts fresh
  test "an expired conversation stops swallowing replies" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    start_goal_chat(s, "quero criar uma meta")

    travel 25.hours
    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "padaria",
                                                     method: "debito", instrument: "itau")) do
      wa_inject(s.jid, "padaria 54,90")
      drain_jobs!
    end

    assert_not GoalConversation.open_for(s.owner), "TTL must have expired the chat"
    assert s.account.transactions.where(source: "whatsapp_text").exists?,
           "the message must flow through the normal pipeline, not the dead chat"
  end

  # WA-GOAL-04 — an expense-looking text mid-chat is a slot answer, not an expense
  test "mid-chat text is consumed by the conversation, never posted as an expense" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    start_goal_chat(s, "quero criar uma meta")
    say s, "1"                        # kind → now collecting the name

    say s, "mercado 54,90"            # would be an expense outside the chat

    goal_names = GoalConversation.open_for(s.owner).data["name"]
    assert_equal "mercado 54,90", goal_names, "the text fills the pending slot"
    assert_not s.account.transactions.where.not(whatsapp_message_id: nil).exists?,
               "nothing may be posted from WA while the chat is open"
  end

  # WA-GOAL-06 (contract-pinned): at the 5-active cap the chat refuses before asking anything
  test "at MAX_ACTIVE the trigger replies limit_reached and opens no conversation" do
    s = E2E::Scenario.build(:history_calibrated).wa_verified!
    5.times do |i|
      s.account.goals.create!(kind: "savings_rate", name: "Meta #{i}", target_cents: 100_000 * (i + 1),
                              status: "active", created_by: s.owner)
    end

    start_goal_chat(s, "quero criar mais uma meta")

    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.goal_flow.limit_reached", locale: :"pt-BR"))
    assert_not GoalConversation.open_for(s.owner)
    assert_equal 5, s.account.goals.count
  end

  # WA-GOAL-05 — "reorganizar" through the real webhook: a slipped purchase goal → the
  # deterministic REPLAN_RE pre-pass (0 LLM) → numbered offer → pick → Goals::Replan applies.
  # The money-trap invariant: Progress#actual_cents is unchanged across the rewrite (last
  # month's savings fold into initial, this month's stay live — counted once). Spec 03 §4.
  test "reorganizar: slipped goal → numbered offer → pick applies replan, actual_cents invariant" do
    s = slipped_goal_scenario
    goal = s.goal
    old_commitment = goal.savings_commitment
    saved_before = Goals::Progress.new(goal).actual_cents
    assert_equal 150_000, saved_before, "pack calibration: R$ 1.500,00 saved into the caixinha"

    wa_inject(s.jid, "reorganizar"); drain_jobs!
    assert_wa_reply s.jid, equals:
      "💙 Meta *Carro*: você já guardou R$ 1.500. Dá pra reorganizar assim:\n" \
      "1. Manter R$ 3.000/mês — termina em fevereiro de 2028\n" \
      "Responde o número, ou *não* pra deixar como está."
    assert GoalConversation.open_for(s.owner).replan_offered?, "single goal jumps straight to the offer"

    wa_inject(s.jid, "1"); drain_jobs!
    assert_wa_reply s.jid, equals:
      "💙 Meta *Carro* reorganizada: R$ 3.000/mês até fevereiro de 2028. Sem culpa — o que importa é continuar."

    goal.reload
    assert_equal 300_000, goal.monthly_target_cents, "extend keeps the parcel"
    assert old_commitment.reload.archived?, "the old savings commitment is archived"
    new_commitment = goal.savings_commitment
    assert new_commitment, "a fresh savings commitment replaces it"
    assert_not_equal old_commitment.id, new_commitment.id
    assert_equal Goals::Progress.new(goal).actual_cents, saved_before,
                 "money-trap: actual_cents is INVARIANT across the rewrite"
    assert_nil GoalConversation.open_for(s.owner), "the chat closes on apply"
  end

  private

  # A genuinely slipped purchase goal (goal_active can't slip — its deadline is a year out):
  # target R$ 60.000, promised Dec/2026, but only R$ 1.500,00 saved → the honest finish slips
  # far past the promise, so ReplanOffer surfaces an extend option. Built like the service twin
  # but with REAL transfers so actual_cents is a live, asserted number.
  def slipped_goal_scenario
    s = E2E::Scenario.build(:solo_basic) { |sc| sc.add_caixinha!; sc.ensure_income_history! }.wa_verified!
    start = Date.current.beginning_of_month << 2
    goal = s.account.goals.create!(
      name: "Carro", kind: "purchase", target_cents: 6_000_000,
      target_date: Date.current.beginning_of_month >> 7, status: "active",
      monthly_target_cents: 300_000, starts_on: start, activated_at: start.in_time_zone,
      bank_account: s.caixinha, created_by: s.owner, baseline: {},
      plan: { "projected_done_on" => (Date.current.beginning_of_month >> 7).iso8601 })
    s.account.commitments.create!(kind: "savings", goal: goal, bank_account: s.itau,
      amount_cents: 300_000, name: "Carro", starts_on: start, schedule_day: 5,
      schedule_kind: "fixed_day", created_by: s.owner)
    s.stash(90_000, on: (Date.current.beginning_of_month << 1) + 4)   # last month → folds into initial
    s.stash(60_000, on: Date.current.beginning_of_month + 4)          # this month → stays live
    s.instance_variable_set(:@goal, goal)
    s
  end

  def start_goal_chat(s, text)
    with_canned_ai(extraction: E2E::CannedAI.create_goal) do
      wa_inject(s.jid, text)
      drain_jobs!
    end
  end

  def say(s, text)
    wa_inject(s.jid, text)   # router replies are zero-LLM
    drain_jobs!
  end

  def walk_to_offer(s)
    start_goal_chat(s, "quero criar uma meta")
    say s, "1"
    say s, "Carro novo"
    say s, "20.000"
    say s, "dezembro"
    say s, "2.000"
  end
end
