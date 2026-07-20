require "test_helper"

# .plans/mobile/04 §3: the bridge's registration POST rides the webview session cookie —
# Current.user AND Current.session come from it (the session FK is the revocation link).
class PushDevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", onboarded_at: Time.current)
  end

  test "registers the device against the signed-in session" do
    sign_in_as(@user)
    assert_difference -> { PushDevice.count } do
      post push_devices_url, params: { token: "tok-9", platform: "ios", app_version: "1.0.0" }
    end
    assert_response :no_content
    device = PushDevice.find_by!(token: "tok-9")
    assert_equal @user, device.user
    assert_equal Session.last, device.session
  end

  test "re-registering the same token upserts instead of duplicating" do
    sign_in_as(@user)
    post push_devices_url, params: { token: "tok-9", platform: "ios" }
    assert_no_difference -> { PushDevice.count } do
      post push_devices_url, params: { token: "tok-9", platform: "ios", app_version: "1.0.1" }
    end
    assert_equal "1.0.1", PushDevice.find_by!(token: "tok-9").app_version
  end

  test "rejects an unknown platform" do
    sign_in_as(@user)
    post push_devices_url, params: { token: "tok-9", platform: "windows" }
    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    post push_devices_url, params: { token: "tok-9", platform: "ios" }
    assert_redirected_to new_session_url
  end
end
