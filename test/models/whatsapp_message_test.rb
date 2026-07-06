require "test_helper"

class WhatsappMessageTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  test "find_or_create_by! on wa_message_id is replay-safe (one row on redelivery)" do
    wa_id = "true_5511999998888@c.us_ABC123"
    2.times do
      begin
        WhatsappMessage.find_or_create_by!(wa_message_id: wa_id) do |m|
          m.direction = "inbound"
          m.message_type = "text"
          m.body = "gastei 13,23 no mercado"
          m.user = @user
        end
      rescue ActiveRecord::RecordNotUnique
        # concurrent redelivery — the unique index makes this a no-op
      end
    end
    assert_equal 1, WhatsappMessage.where(wa_message_id: wa_id).count
  end

  test "enums are string-backed" do
    m = WhatsappMessage.new(direction: "inbound", message_type: "audio")
    assert m.inbound?
    assert m.type_audio?
    assert_equal "received", m.status
  end

  test "linked_transaction association avoids the ActiveRecord transaction-name clash" do
    txn = Transaction.create!(account: @user.account, amount_cents: 500, occurred_on: Date.current)
    m = WhatsappMessage.create!(direction: "outbound", message_type: "text",
                                body: "ok", status: "sent", linked_transaction: txn)
    assert_equal txn, m.linked_transaction
    assert_includes txn.reply_messages, m
  end
end
