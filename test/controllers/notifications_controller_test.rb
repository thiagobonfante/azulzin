require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", onboarded_at: Time.current)
    @notification = Notification.record!(user: @user, account: @user.account,
                                         kind: "bill_due", period_key: Date.new(2026, 7, 10))
  end

  test "dismiss requires authentication" do
    patch dismiss_notification_url(@notification)
    assert_redirected_to new_session_url
    assert_nil @notification.reload.dismissed_at
  end

  test "the alert renders on the dashboard and on the transactions hub" do
    sign_in_as(@user)
    get dashboard_url
    assert_match "notification_#{@notification.id}", response.body

    get transactions_url
    assert_match "notification_#{@notification.id}", response.body
  end

  test "dismiss removes the banner via Turbo Stream and survives reload" do
    sign_in_as(@user)

    patch dismiss_notification_url(@notification), as: :turbo_stream
    assert_response :success
    assert_match %(turbo-stream action="remove" target="notification_#{@notification.id}"), response.body
    assert_not_nil @notification.reload.dismissed_at

    get dashboard_url
    assert_no_match "notification_#{@notification.id}", response.body
  end

  test "dismiss falls back to a redirect for plain HTML" do
    sign_in_as(@user)
    patch dismiss_notification_url(@notification)
    assert_response :redirect
    assert_not_nil @notification.reload.dismissed_at
  end

  test "another user's notification → 404, nothing dismissed" do
    other = users(:english)
    other.update!(onboarded_at: Time.current)
    sign_in_as(other)

    patch dismiss_notification_url(@notification)
    assert_response :not_found
    assert_nil @notification.reload.dismissed_at
  end

  test "a notification from another account (stale membership) → 404" do
    stale = Notification.record!(user: @user, account: accounts(:english),
                                 kind: "card_bill", period_key: Date.new(2026, 7, 10))
    sign_in_as(@user)

    patch dismiss_notification_url(stale)
    assert_response :not_found
    assert_nil stale.reload.dismissed_at
  end
end
