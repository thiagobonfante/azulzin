require "test_helper"

# The intent layer (R9). Extractor is stubbed to return controlled intent-classified extractions;
# the real Matcher / MonthPhrase / commands run. Regression (plain expense) is covered by
# pipeline_test — here we exercise the new verbs and the invariants in 07 §9.
class Whatsapp::InterpreterTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511999998888", whatsapp_id: "5511999998888",
                  phone_verified_at: Time.current, onboarded_at: Time.current)
    @inst = Institution.find_by(code: "260")
    @checking = @user.bank_accounts.create!(institution: @inst, nickname: "Nubank")
    @savings  = @user.bank_accounts.create!(institution: @inst, nickname: "Caixinha", kind: "savings")
    @card     = @user.credit_cards.create!(institution: @inst, nickname: "Roxinho", bill_due_day: 10, closing_offset_days: 10)
  end

  def extraction(**overrides)
    Whatsapp::Extraction.new({
      intent: "expense", intent_confidence: 0.95, amount_raw: nil, amount_cents: nil, currency: "BRL",
      merchant: nil, occurred_on: nil, payment_method: "desconhecido", instrument_phrase: nil,
      field_confidence: { "amount" => 0.95 }, overall_confidence: 0.9, modality: "text", source: "whatsapp_text", raw: {}
    }.merge(overrides))
  end

  def inbound(body, id: "wa-#{SecureRandom.hex(4)}")
    WhatsappMessage.create!(user: @user, direction: "inbound", message_type: "text",
                            wa_message_id: id, chat_id: "x", body: body, status: "received")
  end

  def interpret(msg, ex)
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { ex }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "out-#{SecureRandom.hex(3)}" } }) do
        Whatsapp::Interpreter.new(msg, msg.body).call
      end
    end
  end

  test "guardei 200 na caixinha → one posted transfer to savings; replay creates zero rows" do
    ex = extraction(intent: "transfer", amount_raw: "200", amount_cents: 20_000, to_instrument_phrase: "caixinha")
    msg = inbound("guardei 200 na caixinha")
    interpret(msg, ex)
    t = @user.transactions.where(direction: "transfer").sole
    assert t.posted?
    assert_equal @savings, t.transfer_to_bank_account
    assert_equal @checking, t.bank_account
    assert_no_difference("Transaction.count") { interpret(msg, ex) } # replay same wa_message_id
  end

  test "recebi o salário links to the income and defaults to its account" do
    salary = @user.incomes.create!(bank_account: @checking, name: "salário", amount_cents: 450_000,
                                   schedule_kind: "fixed_day", schedule_day: 5)
    ex = extraction(intent: "income", amount_raw: "4500", amount_cents: 450_000, merchant: "salário")
    interpret(inbound("recebi o salário, 4500"), ex)
    t = @user.transactions.where(direction: "income").sole
    assert_equal salary, t.income
    assert_equal @checking, t.bank_account
    assert salary.received_in?(Date.current.beginning_of_month)
  end

  test "high-confidence installment fans out via the command; replay creates zero rows" do
    ex = extraction(intent: "installment_purchase", amount_raw: "5000", amount_cents: 500_000,
                    installments_count: 10, installment_total_raw: "5000", instrument_phrase: "Roxinho", payment_method: "credito")
    msg = inbound("comprei um celular, 5000 em 10x")
    interpret(msg, ex)
    assert_equal 10, @user.transactions.where.not(installment_number: nil).count
    assert_no_difference("Transaction.count") { interpret(msg, ex) }
  end

  test "low-confidence installment parks ONE stub, never 10 rows" do
    ex = extraction(intent: "installment_purchase", amount_raw: "5000", amount_cents: 500_000,
                    installments_count: 10, installment_total_raw: "5000", instrument_phrase: "inexistente",
                    field_confidence: { "amount" => 0.3 }, overall_confidence: 0.3)
    interpret(inbound("comprei algo em 10x"), ex)
    assert_equal 0, @user.transactions.where.not(installment_number: nil).count
    assert_equal 1, @user.transactions.where(status: "pending_review").count
  end

  test "paguei a parcela do carro marks it paid; repeat month → no second row" do
    carro = @user.commitments.create!(bank_account: @checking, name: "carro financiado", kind: "installment",
                                      amount_cents: 150_000, installments_count: 36, starts_on: Date.current.beginning_of_month << 13)
    ex = extraction(intent: "pay_commitment", commitment_phrase: "carro")
    interpret(inbound("paguei a parcela do carro"), ex)
    assert carro.paid_in?(Date.current.beginning_of_month)
    assert_no_difference -> { carro.payments.posted.count } do
      interpret(inbound("paguei o carro de novo"), ex)
    end
  end

  test "paguei a netflix (card subscription) never creates a payment row (on_bill)" do
    netflix = @user.commitments.create!(credit_card: @card, name: "netflix", kind: "subscription",
                                        amount_cents: 5_590, starts_on: Date.current.beginning_of_month)
    ex = extraction(intent: "pay_commitment", commitment_phrase: "netflix")
    interpret(inbound("paguei a netflix"), ex)
    assert_equal 0, netflix.payments.posted.count
  end

  test "apaga o último resolves via the regex pre-pass with ZERO LLM calls" do
    row = @user.transactions.create!(whatsapp_message: inbound("gastei"), amount_cents: 5_000, occurred_on: Date.current,
                                     status: "posted", direction: "expense", bank_account: @checking, source: "whatsapp_text")
    called = false
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { called = true; extraction }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "o" } }) do
        Whatsapp::Interpreter.new(inbound("apaga o último"), "apaga o último").call
      end
    end
    assert_not called
    assert row.reload.rejected?
  end

  test "query performs zero Transaction writes and opens zero asks" do
    ex = extraction(intent: "query", query_kind: "month_summary")
    assert_no_difference("Transaction.count") { interpret(inbound("como tá o mês"), ex) }
    assert_nil Transaction.open_ask_for(@user)
  end

  test "a mutating intent below the intent floor parks instead of firing the verb" do
    ex = extraction(intent: "transfer", intent_confidence: 0.5, amount_raw: "200", amount_cents: 20_000, to_instrument_phrase: "caixinha")
    interpret(inbound("acho que passei 200"), ex)
    assert_equal 0, @user.transactions.where(direction: "transfer").count
    assert @user.transactions.where(status: "pending_review").exists?
  end
end
