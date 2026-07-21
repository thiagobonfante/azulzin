require "test_helper"

# .plans/mobile/04 §6: FCM message shape, dead-token pruning, and the ≥1-accepted
# semantics Deliver's WA fallback keys on. The transport seam stands in for FCM.
class Notifications::PushSenderTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @session = @user.sessions.create!
    @device  = PushDevice.register!(token: "tok-a", user: @user, session: @session, platform: "ios")
    @sent    = []
  end

  teardown { Notifications::PushSender.transport = nil }

  def transport!(result)
    Notifications::PushSender.transport = ->(payload) { @sent << payload; result }
  end

  test "message carries notification title/body and the data.url deep link" do
    msg = Notifications::PushSender.message("tok-a", "Conta chegando", "Luz vence amanhã.", "/commitments")
    assert_equal "tok-a", msg[:message][:token]
    assert_equal({ title: "Conta chegando", body: "Luz vence amanhã." }, msg[:message][:notification])
    assert_equal({ url: "/commitments" }, msg[:message][:data])
  end

  test "deliver sends to every device and reports success" do
    PushDevice.register!(token: "tok-b", user: @user, session: @session, platform: "android")
    transport!({ ok: true })
    assert Notifications::PushSender.deliver(user: @user, title: "t", body: "b", url: "/dashboard")
    assert_equal %w[tok-a tok-b], @sent.map { |p| p[:message][:token] }.sort
  end

  test "a dead token is pruned and a full failure reports false" do
    transport!({ ok: false, prune: true })
    assert_not Notifications::PushSender.deliver(user: @user, title: "t", body: "b", url: "/dashboard")
    assert_not PushDevice.exists?(token: "tok-a")
  end

  test "a transient failure keeps the device and reports false" do
    transport!({ ok: false })
    assert_not Notifications::PushSender.deliver(user: @user, title: "t", body: "b", url: "/dashboard")
    assert PushDevice.exists?(token: "tok-a")
  end

  test "UNREGISTERED and INVALID_ARGUMENT responses prune; other errors don't" do
    fail404 = Struct.new(:code, :body).new("404", '{"error":{"status":"UNREGISTERED"}}')
    assert Notifications::PushSender.parse(fail404)[:prune]
    fail500 = Struct.new(:code, :body).new("500", "boom")
    assert_not Notifications::PushSender.parse(fail500)[:prune]
  end

  test "configured? is false without credentials or a transport" do
    assert_not Notifications::PushSender.configured? if Rails.application.credentials.firebase.blank?
    transport!({ ok: true })
    assert Notifications::PushSender.configured?
  end
end
