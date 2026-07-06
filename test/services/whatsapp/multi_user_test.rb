require "test_helper"

# Multi-user WhatsApp (spine D6, doc 04 §8): two verified phones share one account. "Whose
# stuff" is the account; "who's talking" is the sender — so money lands in the shared account
# attributed to the sender, and conversation state (open ask, undo referent) is per phone.
class Whatsapp::MultiUserTest < ActiveSupport::TestCase
  setup do
    @owner = users(:confirmed)
    @owner.update!(name: "Thiago", whatsapp_id: "5511111111111", phone_verified_at: Time.current, phone: "5511111111111")
    @account = @owner.account
    @spouse = User.create!(email_address: "spouse@example.com", password: "password123", name: "Bia",
      whatsapp_id: "5522222222222", phone_verified_at: Time.current, phone: "5522222222222")
    @account.memberships.create!(user: @spouse, role: "member")
  end

  def inbound(user, body, id: "wa-#{SecureRandom.hex(4)}")
    WhatsappMessage.create!(user: user, account: user.account, direction: "inbound", message_type: "text",
      wa_message_id: id, chat_id: "#{user.whatsapp_id}@c.us", body: body, status: "received")
  end

  def expense_ex(**o)
    Whatsapp::Extraction.new({ intent: "expense", intent_confidence: 0.95, amount_raw: "50", amount_cents: 5_000,
      currency: "BRL", merchant: "posto", payment_method: "desconhecido", instrument_phrase: nil,
      field_confidence: { "amount" => 0.95 }, overall_confidence: 0.9, modality: "text", source: "whatsapp_text", raw: {} }.merge(o))
  end

  def process_msg(msg, ex = expense_ex)
    Whatsapp::Extractor.stub(:from_text, ->(*_a, **_k) { ex }) do
      WhatsappService.stub(:send_message, ->(_p, _b) { { id: "out-#{SecureRandom.hex(3)}" } }) do
        ProcessInboundWhatsappJob.perform_now(msg.id)
      end
    end
  end

  test "each member's expense lands in the shared account, attributed to the sender" do
    process_msg(inbound(@owner, "gastei 50"))
    process_msg(inbound(@spouse, "gastei 80"), expense_ex(amount_cents: 8_000))
    assert_equal 2, @account.transactions.count
    assert_equal @owner,  @account.transactions.find_by(amount_cents: 5_000).created_by
    assert_equal @spouse, @account.transactions.find_by(amount_cents: 8_000).created_by
    assert @account.transactions.all? { |t| t.account == @account }
  end

  test "open asks are per sender: the husband's answer never resolves the wife's ask" do
    owner_ask  = @account.transactions.create!(created_by: @owner, status: "needs_clarification", amount_cents: 0,
      direction: "expense", occurred_on: Date.current, ask_expires_at: 1.hour.from_now, ask: { "slot" => "amount" })
    spouse_ask = @account.transactions.create!(created_by: @spouse, status: "needs_clarification", amount_cents: 0,
      direction: "expense", occurred_on: Date.current, ask_expires_at: 1.hour.from_now, ask: { "slot" => "amount" })

    assert_equal owner_ask,  Transaction.open_ask_for(@owner)
    assert_equal spouse_ask, Transaction.open_ask_for(@spouse)

    process_msg(inbound(@owner, "50"))   # the husband answers → routed to HIS ask only
    assert owner_ask.reload.posted?
    assert_equal spouse_ask, Transaction.open_ask_for(@spouse), "the wife's ask is untouched"
  end

  test "undo removes only the sender's own last WA row, never the spouse's" do
    owner_row  = @account.transactions.create!(created_by: @owner, status: "posted", direction: "expense",
      amount_cents: 5_000, occurred_on: Date.current, whatsapp_message: inbound(@owner, "x"), source: "whatsapp_text")
    spouse_row = @account.transactions.create!(created_by: @spouse, status: "posted", direction: "expense",
      amount_cents: 8_000, occurred_on: Date.current, whatsapp_message: inbound(@spouse, "y"), source: "whatsapp_text")

    process_msg(inbound(@owner, "apaga o último"))   # regex pre-pass → UndoHandler
    assert owner_row.reload.rejected?, "the sender's own row is undone"
    assert spouse_row.reload.posted?, "the spouse's row is untouched"
  end

  test "a removed member's next message lands in their fresh solo account, not the old shared one" do
    Accounts::RemoveMember.call(@spouse.account_membership)
    new_account = @spouse.reload.account
    assert_not_equal @account, new_account

    process_msg(inbound(@spouse, "gastei 30"), expense_ex(amount_cents: 3_000))
    assert_equal @spouse, new_account.transactions.sole.created_by
    assert_equal 0, @account.transactions.where(created_by: @spouse).count, "nothing new in the old account"
  end
end
