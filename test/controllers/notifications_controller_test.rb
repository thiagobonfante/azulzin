require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", onboarded_at: Time.current)
    # Payload shape as Reminders::Scan produces it — the plural bill_due copy needs it to render.
    @notification = Notification.record!(user: @user, account: @user.account,
                                         kind: "bill_due", period_key: Date.new(2026, 7, 10),
                                         payload: { "name" => "Luz", "amount_cents" => 18_240,
                                                    "due_on" => "2026-07-10", "days_until" => 1 })
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

  # up-tier 03 §5.2 — the rightsize banner's ONE TAP: a preset categories#update PATCH
  # lowering the budget to the typical (median) value; the plain-HTML submit redirects to
  # the categories index. budget_warn/breach banners deep-link to the same index.
  test "the rightsize banner one-taps the budget down to the typical value" do
    category = @user.account.categories.create!(name: "Lazer", monthly_budget_cents: 60_000)
    Notification.record!(user: @user, account: @user.account, kind: "rightsize_budget",
                         subject: category, period_key: Date.new(2026, 7, 1),
                         payload: { "category" => "Lazer", "budget_cents" => 60_000,
                                    "typical_cents" => 30_000 })
    sign_in_as(@user)

    get dashboard_url
    assert_match category_path(category), response.body
    assert_match "category[monthly_budget_reais]", response.body

    patch category_url(category), params: { category: { monthly_budget_reais: "300,00" } }
    assert_redirected_to categories_path
    assert_equal 30_000, category.reload.monthly_budget_cents
  end

  test "budget banners deep-link to the category on the categories index" do
    category = @user.account.categories.create!(name: "Restaurantes", monthly_budget_cents: 60_000)
    Notification.record!(user: @user, account: @user.account, kind: "budget_warn",
                         subject: category, period_key: Date.new(2026, 7, 1),
                         payload: { "category" => "Restaurantes", "spent_cents" => 50_000,
                                    "budget_cents" => 60_000, "left_cents" => 10_000 })
    sign_in_as(@user)

    get dashboard_url
    assert_match "#{categories_path}#category_#{category.id}", response.body
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
                                 kind: "card_due", period_key: Date.new(2026, 7, 10))
    sign_in_as(@user)

    patch dismiss_notification_url(stale)
    assert_response :not_found
    assert_nil stale.reload.dismissed_at
  end
end
