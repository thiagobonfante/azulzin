require "test_helper"

# End-to-end decision pipeline through the job: real Matcher/Confidence/Decider, with the
# AI (Extractor) and the sidecar (WhatsappService) stubbed. Exercises the DECIDED silent
# auto-commit posture (Open Decision #5).
class Whatsapp::PipelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @card = CreditCard.create!(account: @user.account, institution: Institution.find_by(code: "260")) # Nubank
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      amount_raw: "13,23", amount_cents: 1_323, currency: "BRL", merchant: "supermercado",
      occurred_on: nil, payment_method: "credito", instrument_phrase: "cartão Nubank",
      field_confidence: { "amount" => 0.95 }, overall_confidence: 0.9,
      modality: "text", source: "whatsapp_text", raw: {}
    }.merge(overrides))
  end

  def inbound(body, id: "wa-#{SecureRandom.hex(4)}")
    WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
      wa_message_id: id, chat_id: "5511999998888@c.us", body: body, status: "received")
  end

  def run_pipeline(msg, ex = nil)
    stub_ex = ex || extraction
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { stub_ex }) do
      WhatsappService.stub(:send_message, ->(_p, b) { (@sent ||= []) << b; { id: "out-#{SecureRandom.hex(3)}" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end
  end

  test "high confidence + matched instrument → posted, assigned silently" do
    run_pipeline(inbound("gastei 13,23 no supermercado no cartão Nubank"))
    txn = @user.account.transactions.sole
    assert txn.posted?
    assert_equal @card, txn.credit_card
    assert_equal 1_323, txn.amount_cents
    assert txn.confirmed_at.present?
    assert_includes @sent.last, "no cartão #{@card.display_name}"   # confirmation names the KIND
  end

  test "confirmation copy says conta for a bank-account expense" do
    itau = BankAccount.create!(account: @user.account, institution: Institution.find_by(code: "341"))
    run_pipeline(inbound("gastei 20 no débito itau"),
                 extraction(amount_cents: 2_000, payment_method: "debito", instrument_phrase: "itau"))
    txn = @user.account.transactions.sole
    assert_equal itau, txn.bank_account
    assert_includes @sent.last, "na conta #{itau.display_name}"
  end

  test "high confidence + unmatched instrument → posted UNASSIGNED (assign in-app)" do
    # payment_method "desconhecido" → KIND isn't decisive → no auto-assign → unassigned.
    run_pipeline(inbound("gastei 50 no posto"),
                 extraction(amount_cents: 5_000, instrument_phrase: nil, payment_method: "desconhecido", merchant: "posto"))
    txn = @user.account.transactions.sole
    assert txn.posted?
    assert_not txn.assigned?
  end

  test "shaky amount (below floor) → parked, not posted" do
    run_pipeline(inbound("acho que gastei uns 30"),
        extraction(amount_cents: 3_000, field_confidence: { "amount" => 0.4 }, overall_confidence: 0.4))
    txn = @user.account.transactions.sole
    assert txn.pending_review?
  end

  test "missing amount → asks, then a follow-up amount posts it (open-ask routing)" do
    run_pipeline(inbound("comprei no Nubank"), extraction(amount_raw: nil, amount_cents: nil))
    ask = @user.account.transactions.sole
    assert ask.needs_clarification?
    assert_equal "amount", ask.ask["slot"]
    assert_equal @card, ask.credit_card               # instrument resolved at ask time

    run_pipeline(inbound("137,90"))                            # open-ask path → ReplyRouter (no extractor call)
    ask.reload
    assert ask.posted?
    assert_equal 13_790, ask.amount_cents
    assert_equal 1, @user.account.transactions.count          # no second transaction
    assert_includes @sent.last, "no cartão #{@card.display_name}"  # amount-resolution also forks the copy
  end

  # --- Round 3 P5 regressions: numbered replies follow PROMPT order; a transfer with both
  # legs unmatched chains a second ask instead of posting half a transfer (nil source).

  test "transfer with both legs unmatched: numbered replies resolve in prompt order and chain the missing leg" do
    inst = ->(code) { Institution.find_by(code: code) }
    santander = BankAccount.create!(account: @user.account, institution: inst.("033"))
    nubank_t  = BankAccount.create!(account: @user.account, institution: inst.("260"), nickname: "Nubank (Thiago)")
    nubank_f  = BankAccount.create!(account: @user.account, institution: inst.("260"), nickname: "Nubank (Fran)")
    bb        = BankAccount.create!(account: @user.account, institution: inst.("001"))
    savings_account  = BankAccount.create!(account: @user.account, institution: inst.("260"), nickname: "Caixinha", kind: "savings")

    run_pipeline(inbound("transferi 300 pra outra conta"),
                 extraction(intent: "transfer", intent_confidence: 0.95, amount_raw: "300", amount_cents: 30_000,
                            merchant: nil, payment_method: "desconhecido",
                            instrument_phrase: "misteriosa", to_instrument_phrase: "desconhecida"))
    ask = @user.account.transactions.where(direction: "transfer").sole
    assert_equal "transfer_to", ask.ask["slot"]
    # Prompt order: savings first (kind: :desc), then created_at — NOT PK order.
    prompt_order = [ savings_account, santander, nubank_t, nubank_f, bb ].map(&:id)
    assert_equal prompt_order, ask.ask["options"]

    run_pipeline(inbound("4"))     # 4th PROMPT item = Nubank (Fran); PK order would give BB
    ask.reload
    assert_equal nubank_f.id, ask.transfer_to_bank_account_id
    assert_not ask.posted?, "must never post a transfer with a nil source leg"
    assert_equal "transfer_from", ask.ask["slot"]                  # chained ask for the other leg
    assert_operator ask.ask_expires_at, :>, Time.current           # not born expired
    assert_includes @sent.last, "1. #{savings_account.display_name}"      # numbered options re-sent

    run_pipeline(inbound("2"))     # 2nd prompt item = Santander
    ask.reload
    assert ask.posted?
    assert_equal santander.id, ask.bank_account_id
    assert_equal nubank_f.id, ask.transfer_to_bank_account_id
    assert_includes @sent.last, santander.display_name             # confirmation carries BOTH names
    assert_includes @sent.last, nubank_f.display_name
    assert_not @user.account.transactions.posted.where(direction: "transfer", bank_account_id: nil).exists?
  end

  test "a chained transfer leg re-asks when the reply picks the already-resolved leg" do
    inst260 = Institution.find_by(code: "260")
    a = BankAccount.create!(account: @user.account, institution: inst260, nickname: "Conta A")
    b = BankAccount.create!(account: @user.account, institution: inst260, nickname: "Conta B")

    run_pipeline(inbound("transferi 100"),
                 extraction(intent: "transfer", intent_confidence: 0.95, amount_raw: "100", amount_cents: 10_000,
                            merchant: nil, payment_method: "desconhecido",
                            instrument_phrase: "misteriosa", to_instrument_phrase: "desconhecida"))
    ask = @user.account.transactions.where(direction: "transfer").sole
    run_pipeline(inbound("1"))     # destination = Conta A
    run_pipeline(inbound("1"))     # source = Conta A again → invalid, re-ask (never posts same-account)
    ask.reload
    assert_not ask.posted?
    assert_equal "transfer_from", ask.ask["slot"]
    run_pipeline(inbound("2"))     # source = Conta B → posts
    ask.reload
    assert ask.posted?
    assert_equal b.id, ask.bank_account_id
    assert_equal a.id, ask.transfer_to_bank_account_id
  end

  test "in-app safety net: reverse and reassign" do
    run_pipeline(inbound("gastei 13,23 no cartão Nubank"))
    txn = @user.account.transactions.sole
    other = BankAccount.create!(account: @user.account, institution: Institution.find_by(code: "341"))
    txn.assign_instrument!(other)
    assert_equal other, txn.bank_account
    assert_nil txn.credit_card
    txn.reverse!
    assert txn.rejected?
    assert_equal 0, @user.account.transactions.spend.count
  end

  # --- Phase 0 regression: the pipeline is unchanged except every row now carries a billing_month.

  test "regression: a posted WA expense on an UNCONFIGURED card buckets by calendar month" do
    run_pipeline(inbound("gastei 13,23 no mercado no cartão Nubank"))
    txn = @user.account.transactions.sole
    assert txn.posted?
    assert_equal @card, txn.credit_card
    assert_equal txn.occurred_on.beginning_of_month, txn.billing_month
  end

  test "a WA expense on a CONFIGURED card buckets by the closing rule (d10/f7, 07-04 → August)" do
    @card.update!(bill_due_day: 10, closing_offset_days: 7)
    run_pipeline(inbound("gastei 13,23 no cartão Nubank"), extraction(occurred_on: Date.new(2026, 7, 4)))
    txn = @user.account.transactions.sole
    assert_equal @card, txn.credit_card
    assert_equal Date.new(2026, 8, 1), txn.billing_month
  end
end
