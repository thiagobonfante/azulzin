require "test_helper"

# The WA conversational goal-creation flow end-to-end through the job (round 3 P6):
# trigger (one stubbed Extractor call) → deterministic slot Q&A → single recomendado offer →
# always-linked activation. Replies after the trigger run with the Extractor stub RAISING —
# proving zero LLM calls. Ledger: capacity = 900k − 200k = R$7.000/mês, Restaurantes trimmable.
class Whatsapp::GoalFlowTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  WINDOW = [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ].freeze

  setup do
    # Freeze FIRST: rows created before travel_to carry the real clock, which sorts AFTER the
    # frozen date once the real world passes it — inverting every created_at ordering (the
    # savings_account picker prompts started listing test-created accounts first on 2026-07-15).
    travel_to Time.utc(2026, 7, 15, 12)
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @account = @user.account
    @inst = Institution.find_by(code: "260")
    @checking = @account.bank_accounts.create!(institution: @inst, nickname: "Corrente", kind: "checking")
    @savings_account = @account.bank_accounts.create!(institution: @inst, nickname: "Caixinha", kind: "savings")
    @rest = @account.categories.create!(name: "Restaurantes")
    seed_ledger
  end

  teardown { travel_back }

  def seed_ledger
    WINDOW.each do |m|
      @account.transactions.create!(direction: "income", status: "posted", amount_cents: 900_000,
                                    bank_account: @checking, occurred_on: m, billing_month: m, billing_month_manual: true)
      10.times do
        @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 20_000,
                                      category: @rest, bank_account: @checking, occurred_on: m,
                                      billing_month: m, billing_month_manual: true)
      end
    end
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      intent: "create_goal", intent_confidence: 0.95, amount_raw: nil, amount_cents: nil,
      currency: "BRL", merchant: nil, occurred_on: nil, payment_method: "desconhecido",
      instrument_phrase: nil, field_confidence: {}, overall_confidence: 0.9,
      modality: "text", source: "whatsapp_text", raw: {}
    }.merge(overrides))
  end

  def inbound(body, id: "wa-#{SecureRandom.hex(4)}")
    WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
                            wa_message_id: id, chat_id: "x", body: body, status: "received")
  end

  # ex nil ⇒ the Extractor stub RAISES — every reply after the trigger must be LLM-free.
  def run_pipeline(msg, ex = nil)
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { ex or raise "LLM called after the trigger" }) do
      WhatsappService.stub(:send_message, ->(_p, b) { (@sent ||= []) << b; { id: "out-#{SecureRandom.hex(3)}" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end
  end

  def conv = GoalConversation.order(:created_at).last

  # ---- happy paths ---------------------------------------------------------------------

  test "purchase: trigger → month → initial → offer → sim → active goal + parcelado commitment, zero LLM after trigger" do
    run_pipeline(inbound("quero juntar 60 mil pra um carro"),
                 extraction(goal_kind: "purchase", goal_name: "Carro", amount_raw: "60000"))
    assert_equal "month", conv.data["pending_slot"]   # kind/name/amount seeded from the trigger

    run_pipeline(inbound("dezembro de 2027"))
    assert_equal "2027-12-01", conv.data["target_month"]
    assert_equal "initial_saved", conv.data["pending_slot"]

    run_pipeline(inbound("não"))
    assert conv.offered?
    goal = @account.goals.sole
    assert goal.draft?
    assert_equal 6_000_000, goal.target_cents
    assert goal.baseline["median_capacity_base_cents"].present?, "baseline analyzed in-job before save"
    # required = ⌈6.000.000 / 16 months⌉ = 375.000 ≤ capacity → no cuts
    assert_includes @sent.last, "3.750"
    assert_includes @sent.last, "Sem cortes"
    assert_includes @sent.last, "*sim*"

    run_pipeline(inbound("sim"))
    goal.reload
    assert goal.active?
    assert_equal Date.new(2026, 8, 1), goal.starts_on, "starts next month"
    assert_equal @savings_account, goal.bank_account
    c = goal.savings_commitment
    assert_equal @checking, c.bank_account
    assert_equal 375_000, c.amount_cents
    assert_equal Date.new(2027, 11, 1), c.ends_on   # 16 parcels from 2026-08
    assert conv.closed?
    assert_includes @sent.last, "ativada"
  end

  test "savings_rate: zero-guardado ask, default name, open-ended commitment" do
    run_pipeline(inbound("quero guardar mais todo mês"), extraction(goal_kind: "savings_rate"))
    assert_equal "amount", conv.data["pending_slot"]
    assert_includes @sent.last, "guardar por mês"   # zero variant (no guardado anchor)

    run_pipeline(inbound("1000"))
    assert conv.offered?
    run_pipeline(inbound("sim"))
    goal = @account.goals.sole
    assert goal.active?
    assert_equal "Guardar mais", goal.name          # localized kind title default
    assert_equal 100_000, goal.monthly_target_cents
    assert_nil goal.savings_commitment.ends_on      # open-ended (fixo-like)
    assert conv.closed?
  end

  test "unknown kind asks a numbered pick first" do
    run_pipeline(inbound("quero criar uma meta"), extraction)
    assert_equal "kind", conv.data["pending_slot"]
    assert_includes @sent.last, "1. Comprar algo"
    run_pipeline(inbound("1"))
    assert_equal "purchase", conv.data["kind"]
    assert_equal "name", conv.data["pending_slot"]
  end

  test "unparseable slot answers re-ask with an example and keep the conversation open" do
    run_pipeline(inbound("meta"), extraction(goal_kind: "purchase", goal_name: "Casa", amount_raw: "50000"))
    run_pipeline(inbound("sei lá"))                 # month unparseable
    assert_includes @sent.last, "outubro de 2027"   # re-ask example
    assert conv.collecting?
    run_pipeline(inbound("em 20 meses"))
    assert_equal "2028-03-01", conv.data["target_month"]
  end

  # ---- cancel / reject / expiry destroy the draft --------------------------------------

  test "cancelar at the offer destroys the draft and closes the conversation" do
    reach_offer
    assert_equal 1, @account.goals.count
    run_pipeline(inbound("cancelar"))
    assert_equal 0, @account.goals.count
    assert conv.closed?
  end

  test "não at the offer destroys the draft (invisible drafts leak the AI quota)" do
    reach_offer
    run_pipeline(inbound("não"))
    assert_equal 0, @account.goals.count
    assert conv.closed?
    assert_includes @sent.last, "descartei"
  end

  test "expired conversation is inert; the next flow start lazily destroys its draft" do
    reach_offer
    stale = conv
    draft = @account.goals.sole
    travel 25.hours
    run_pipeline(inbound("sim"), extraction(intent: "other", intent_confidence: 0.9))  # falls to interpreter
    assert draft.reload.draft?, "passive expiry never touches the draft by itself"

    run_pipeline(inbound("quero guardar mais"), extraction(goal_kind: "savings_rate"))
    assert_not Goal.exists?(draft.id), "stale draft destroyed on next start"
    assert stale.reload.closed?
    assert conv.collecting?
  end

  test "double sim can't activate twice (guarded transition around Activate)" do
    reach_offer
    stale = conv                       # in-memory status still "offered" after the pipeline closes it
    run_pipeline(inbound("sim"))
    assert @account.goals.sole.active?
    assert_no_difference [ "Commitment.count", "Goal.count" ] do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "x" } }) do
        Whatsapp::GoalFlowRouter.new(stale, inbound("sim"), "sim").call
      end
    end
  end

  # ---- guards and counter-offers --------------------------------------------------------

  test "savings target at or below the current guardado re-asks the amount" do
    WINDOW.each do |m|
      @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 50_000,
                                    bank_account: @checking, transfer_to_bank_account: @savings_account,
                                    occurred_on: m, billing_month: m, billing_month_manual: true)
    end
    run_pipeline(inbound("quero guardar 400 por mês"),
                 extraction(goal_kind: "savings_rate", amount_raw: "400"))
    assert_includes @sent.last, "500"               # floored guardado anchor in the re-ask
    assert conv.collecting?
    assert_equal "amount", conv.data["pending_slot"]
    assert_equal 0, @account.goals.count            # no doomed draft saved

    run_pipeline(inbound("600"))
    assert conv.offered?
  end

  test "infeasible purchase: honest date counter-offer, sim auto-applies and re-presents, sim activates" do
    run_pipeline(inbound("quero juntar 100 mil pra uma casa até dezembro"),
                 extraction(goal_kind: "purchase", goal_name: "Casa", amount_raw: "100000",
                            goal_month_phrase: "em 5 meses"))
    run_pipeline(inbound("não"))                    # initial saved: none
    # required 2.500.000/mês > achievable 780.000 → counter-offer with the feasible date
    assert conv.offered?
    assert_equal "2027-09-01", conv.data.dig("counter", "target_date")
    assert_includes @sent.last, "7.800"

    run_pipeline(inbound("sim"))                    # auto-applies the date, re-presents the plan
    goal = @account.goals.sole
    assert_equal Date.new(2027, 9, 1), goal.reload.target_date
    assert goal.draft?
    assert_nil conv.data["counter"]
    assert_includes @sent.last, "Quer ativar?"

    run_pipeline(inbound("sim"))
    assert goal.reload.active?
  end

  test "too tight (achievable ≤ 0): honest refusal, draft destroyed, conversation closed" do
    4.times do |i|
      @account.goals.create!(name: "Meta #{i}", kind: "savings_rate", target_cents: 200_000,
                             monthly_target_cents: 200_000, status: "active", starts_on: Date.new(2026, 8, 1))
    end
    run_pipeline(inbound("quero guardar 1000 por mês"),
                 extraction(goal_kind: "savings_rate", amount_raw: "1000"))
    assert_includes @sent.last, "não fecha"
    assert_equal 0, @account.goals.draft.count
    assert conv.closed?
  end

  test "at MAX_ACTIVE the flow refuses to start" do
    5.times do |i|
      @account.goals.create!(name: "Meta #{i}", kind: "savings_rate", target_cents: 100_000,
                             monthly_target_cents: 100_000, status: "active", starts_on: Date.new(2026, 8, 1))
    end
    run_pipeline(inbound("quero criar uma meta"), extraction)
    assert_nil GoalConversation.open_for(@user)
    assert_includes @sent.last, "5 metas"
  end

  # ---- always-linked accept (decision 4) -------------------------------------------------

  test "no savings account: sim blocks with the create-a-savings account nudge, draft destroyed, closed" do
    @savings_account.update!(kind: "checking")             # household has no savings account
    reach_offer
    run_pipeline(inbound("sim"))
    assert_equal 0, @account.goals.count
    assert conv.closed?
    assert_includes @sent.last, "poupança"
  end

  test "no distinct source (savings account is the only account): same block" do
    @account.transactions.update_all(bank_account_id: nil)   # free the checking account
    @checking.soft_delete!(by: @user)
    reach_offer
    run_pipeline(inbound("sim"))
    assert_equal 0, @account.goals.count
    assert conv.closed?
    assert_includes @sent.last, "poupança"
  end

  test "2 savings accounts and 3 sources: numbered picks in prompt order, then activation" do
    savings_account2 = @account.bank_accounts.create!(institution: @inst, nickname: "Sonhos", kind: "savings")
    checking2 = @account.bank_accounts.create!(institution: @inst, nickname: "Itaú", kind: "checking")
    reach_offer
    run_pipeline(inbound("sim"))
    assert conv.picking_caixinha?
    assert_equal [ @savings_account.id, savings_account2.id ], conv.data["options"]   # prompt order stored
    assert_includes @sent.last, "1. Caixinha"

    run_pipeline(inbound("2"))                      # → Sonhos
    assert conv.picking_source?
    assert_equal [ @checking.id, @savings_account.id, checking2.id ], conv.data["options"]

    run_pipeline(inbound("3"))                      # → Itaú
    goal = @account.goals.sole
    assert goal.active?
    assert_equal savings_account2, goal.bank_account
    assert_equal checking2, goal.savings_commitment.bank_account
    assert conv.closed?
  end

  test "gibberish pick re-asks with the same numbered options" do
    @account.bank_accounts.create!(institution: @inst, nickname: "Sonhos", kind: "savings")
    reach_offer
    run_pipeline(inbound("sim"))
    run_pipeline(inbound("xyzzy"))
    assert conv.picking_caixinha?
    assert_includes @sent.last, "1. Caixinha"
  end

  # ---- precedence -----------------------------------------------------------------------

  test "an open txn ask eats the reply before the goal conversation" do
    run_pipeline(inbound("gastei no mercado"),
                 extraction(intent: "expense", merchant: "mercado", overall_confidence: 0.9,
                            field_confidence: { "amount" => 0.9 }))
    ask = Transaction.open_ask_for(@user)
    assert_equal "amount", ask.ask["slot"]
    @account.goal_conversations.create!(user: @user, status: "collecting",
      data: { "kind" => "purchase", "name" => "Casa", "pending_slot" => "amount" },
      expires_at: 1.day.from_now)

    run_pipeline(inbound("137,90"))
    assert_equal 13_790, ask.reload.amount_cents    # the txn ask won
    assert_nil conv.data["target_cents"], "goal conversation untouched"
  end

  # ---- reorganizar (round 4) — every turn runs with the Extractor stub RAISING: zero LLM --

  test "reorganizar with one goal: offer → '1' applies extend, commitment swapped, chat closed" do
    goal = replannable_goal!
    old_commitment = goal.savings_commitment

    run_pipeline(inbound("reorganizar"))
    assert_match "Carro", @sent.last
    assert_match "1.", @sent.last                       # numbered options in the offer
    assert GoalConversation.open_for(@user).replan_offered?

    run_pipeline(inbound("1"))
    assert_match "reorganizada", @sent.last
    goal.reload
    assert_equal 300_000, goal.monthly_target_cents     # extend keeps the parcel
    assert_equal Date.new(2026, 8, 1), goal.starts_on   # re-anchored next month
    assert old_commitment.reload.archived?
    assert goal.savings_commitment
    assert_nil GoalConversation.open_for(@user)
  end

  test "reorganizar with no active purchase goal: friendly nudge, no conversation" do
    run_pipeline(inbound("reorganizar"))
    assert_equal I18n.t("whatsapp.replies.goal_replan.none"), @sent.last
    assert_nil GoalConversation.open_for(@user)
  end

  test "reorganizar with two goals: numbered pick, then 'sim' applies the first option" do
    replannable_goal!(name: "Carro")
    viagem = replannable_goal!(name: "Viagem", monthly: 100_000)

    run_pipeline(inbound("reorganizar meta"))
    assert_match "1. Carro", @sent.last
    assert_match "2. Viagem", @sent.last

    run_pipeline(inbound("2"))
    assert GoalConversation.open_for(@user).replan_offered?
    assert_match "Viagem", @sent.last

    run_pipeline(inbound("sim"))                        # first option = extend
    assert_equal 100_000, viagem.reload.monthly_target_cents
    assert_equal Date.new(2026, 8, 1), viagem.starts_on
  end

  test "reorganizar offer answered 'não' keeps the plan untouched and closes the chat" do
    goal = replannable_goal!
    before = goal.attributes.slice("monthly_target_cents", "target_date", "starts_on")
    run_pipeline(inbound("reorganizar"))
    run_pipeline(inbound("não"))
    assert_equal I18n.t("whatsapp.replies.goal_replan.kept"), @sent.last
    assert_equal before, goal.reload.attributes.slice("monthly_target_cents", "target_date", "starts_on")
    assert_nil GoalConversation.open_for(@user)
  end

  test "reorganizar supersedes an open goal-creation chat (one open per user)" do
    replannable_goal!
    stale = @account.goal_conversations.create!(user: @user, status: "collecting",
      data: { "kind" => "purchase", "pending_slot" => "name" }, expires_at: 1.day.from_now)
    run_pipeline(inbound("reorganizar"))
    assert stale.reload.closed?
    assert GoalConversation.open_for(@user).replan_offered?
  end

  test "reorganizar mid-creation with nothing to replan keeps the draft and the chat (review fix)" do
    reach_offer
    draft = conv.goal
    assert draft.draft?
    run_pipeline(inbound("reorganizar"))
    assert_equal I18n.t("whatsapp.replies.goal_replan.none"), @sent.last
    assert draft.reload.draft?, "half-built draft survives"
    assert conv.reload.offered?, "creation chat survives"
    run_pipeline(inbound("sim"))                        # and the flow continues to activation
    assert conv.reload.closed?
    assert draft.reload.active?
  end

  test "a replan that can no longer apply gets the unavailable copy, not a dead-end retry (review fix)" do
    goal = replannable_goal!
    run_pipeline(inbound("reorganizar"))
    assert GoalConversation.open_for(@user).replan_offered?
    @account.transactions.create!(direction: "transfer", status: "posted", amount_cents: 6_000_000,
                                  bank_account: @checking, transfer_to_bank_account: @savings_account,
                                  occurred_on: Date.new(2026, 7, 15), billing_month: Date.new(2026, 7, 1),
                                  billing_month_manual: true)   # target reached between offer and reply
    run_pipeline(inbound("1"))
    assert_equal I18n.t("whatsapp.replies.goal_replan.unavailable"), @sent.last
    assert goal.reload.active?, "nothing was rewritten"
  end

  private

  def replannable_goal!(name: "Carro", monthly: 300_000)
    goal = @account.goals.create!(name:, kind: "purchase", target_cents: 6_000_000,
      target_date: Date.new(2027, 12, 1), status: "active", monthly_target_cents: monthly,
      starts_on: Date.new(2026, 6, 1), activated_at: Time.utc(2026, 5, 20),
      bank_account: @savings_account, baseline: {}, plan: { "projected_done_on" => "2028-02-01" })
    @account.commitments.create!(kind: "savings", goal:, bank_account: @checking,
      amount_cents: monthly, name:, starts_on: goal.starts_on,
      schedule_day: 5, schedule_kind: "fixed_day")
    goal
  end

  # Trigger + slot answers up to the feasible offer (single savings_account/source unless changed).
  def reach_offer
    run_pipeline(inbound("quero juntar 60 mil pra um carro"),
                 extraction(goal_kind: "purchase", goal_name: "Carro", amount_raw: "60000"))
    run_pipeline(inbound("dezembro de 2027"))
    run_pipeline(inbound("não"))
    assert conv.offered?
  end
end
