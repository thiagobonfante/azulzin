require "test_helper"

# The auto-categorization ladder through the real pipeline (01 §5): merchant memory
# (human rows only) outranks the LLM's label guess; provenance is stamped either way.
class Whatsapp::CategorizationTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @user.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current, phone: "5511999998888")
    @card = CreditCard.create!(account: @user.account, institution: Institution.find_by(code: "260"))
    Categories::SeedDefaults.call(@user.account, locale: "pt-BR")
    @mercado = @user.account.categories.find_by(name: "Mercado")
    @saude   = @user.account.categories.find_by(name: "Saúde")
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

  def run_pipeline(msg, ex)
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { ex }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "out-#{SecureRandom.hex(3)}" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end
  end

  def human_spend!(merchant, category)
    @user.account.transactions.create!(
      created_by: @user, direction: "expense", status: "posted", confirmed_at: Time.current,
      amount_cents: 1_000, merchant: merchant, occurred_on: Date.current,
      category_id: category.id, category_source: "user", source: "manual"
    )
  end

  test "LLM label guess resolves and stamps ai" do
    run_pipeline(inbound("250 na farmácia"), extraction(merchant: "farmácia são joão", category: "saude"))
    txn = @user.account.transactions.where(source: "whatsapp_text").sole
    assert_equal @saude, txn.category
    assert_equal "ai", txn.category_source
  end

  test "merchant memory outranks the LLM guess and stamps memory" do
    human_spend!("Zaffari", @mercado)
    run_pipeline(inbound("80 no zaffari"), extraction(merchant: "Zaffari", category: "lazer"))
    txn = @user.account.transactions.where(source: "whatsapp_text").sole
    assert_equal @mercado, txn.category       # memory won over "lazer"
    assert_equal "memory", txn.category_source
  end

  test "memory rows created by the machine do not self-reinforce" do
    run_pipeline(inbound("30 no uber"), extraction(merchant: "uber", category: "transporte"))
    first = @user.account.transactions.where(source: "whatsapp_text").sole
    assert_equal "ai", first.category_source

    run_pipeline(inbound("outros 30 no uber"), extraction(merchant: "uber", category: "lazer"))
    second = @user.account.transactions.where(source: "whatsapp_text").order(:id).last
    # No human row exists for uber → the ladder falls through to the (new) LLM guess.
    assert_equal "ai", second.category_source
    assert_equal @user.account.categories.find_by(name: "Lazer"), second.category
  end

  test "edit_last category: 'muda pra mercado' recategorizes the last WA row and stamps user" do
    run_pipeline(inbound("30 no zaffari"), extraction(merchant: "Zaffari", category: "lazer"))
    txn = @user.account.transactions.where(source: "whatsapp_text").sole
    assert_equal "ai", txn.category_source

    edit = extraction(intent: "edit_last", intent_confidence: 0.95, edit_field_hint: "category",
                      amount_raw: nil, amount_cents: nil, category: "mercado", merchant: nil,
                      instrument_phrase: nil)
    run_pipeline(inbound("muda a categoria pra mercado"), edit)
    txn.reload
    assert_equal @mercado, txn.category
    assert_equal "user", txn.category_source   # spoken correction = human signal, feeds memory
  end

  test "no guess, no memory → uncategorized with null provenance" do
    run_pipeline(inbound("50 sei lá onde"), extraction(merchant: "loja aleatória", category: nil))
    txn = @user.account.transactions.where(source: "whatsapp_text").sole
    assert_nil txn.category_id
    assert_nil txn.category_source
  end
end
