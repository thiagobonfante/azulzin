require "test_helper"

# .plans/mobile/04 §2: upsert-by-token semantics and the session revocation linkage.
class PushDeviceTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @session = @user.sessions.create!
  end

  test "register! upserts by token — the token's current user and session win" do
    PushDevice.register!(token: "tok-1", user: @user, session: @session, platform: "ios")
    other         = users(:unconfirmed)
    other_session = other.sessions.create!
    device = PushDevice.register!(token: "tok-1", user: other, session: other_session,
                                  platform: "android", app_version: "1.1.0")
    assert_equal 1, PushDevice.where(token: "tok-1").count
    assert_equal other, device.user
    assert_equal "android", device.platform
    assert_equal "1.1.0", device.app_version
  end

  test "destroying the session revokes its devices" do
    PushDevice.register!(token: "tok-2", user: @user, session: @session, platform: "ios")
    @session.destroy!
    assert_not PushDevice.exists?(token: "tok-2")
  end

  test "platform is whitelisted" do
    assert_raises(ActiveRecord::RecordInvalid) do
      PushDevice.register!(token: "tok-3", user: @user, session: @session, platform: "windows")
    end
  end
end
