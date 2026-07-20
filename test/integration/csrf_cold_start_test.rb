require "test_helper"

# Native cold-start CSRF race (.plans/mobile/handoff.md "Known gaps"): the shells open
# every tab in parallel on launch. The durable session_id cookie is permanent, but the
# Rails cookie session (home of _csrf_token) dies with the app process — so N parallel
# GETs each mint a different token and only the last Set-Cookie wins the shared jar,
# orphaning every other page's form. These tests simulate exactly that: parallel
# cookieless GETs, then a POST carrying the FIRST page's token under the LAST page's
# cookie.
class CsrfColdStartTest < ActionDispatch::IntegrationTest
  NATIVE_UA = "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; Azulzin/1.0.0"

  setup do
    ActionController::Base.allow_forgery_protection = true
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
  end

  def native = { "User-Agent" => NATIVE_UA }

  # The Rails session cookie is everything except the durable session_id.
  def drop_rails_session_cookie
    cookies.to_hash.keys.each { |name| cookies.delete(name) unless name == "session_id" }
  end

  def form_token(action)
    # form_with url: may render a full URL — match on the path suffix.
    assert_select "form[action$=?] input[name=authenticity_token]", action do |inputs|
      return inputs.first["value"]
    end
  end

  test "signed-in cold start: first page's token verifies under the last page's cookie" do
    sign_in_as(@user)

    get chat_url, headers: native                  # tab 1 mints a cookie session
    assert_response :success
    token = form_token(chat_messages_path)

    drop_rails_session_cookie                      # tab 2 races in cookieless…
    get dashboard_url, headers: native             # …and its Set-Cookie wins the jar
    assert_response :success

    assert_difference -> { ChatMessage.where(direction: "inbound").count } do
      post chat_messages_url, headers: native,
        params: { authenticity_token: token, chat_message: { body: "mercado 10" } }
    end
    assert_response :redirect
  end

  test "signed-out native cold start: sign-in POST succeeds with an orphaned token" do
    get new_session_url, headers: native           # visible tab renders the form
    assert_response :success
    token = form_token(session_path)

    cookies.to_hash.keys.each { |name| cookies.delete(name) }
    get new_session_url, headers: native           # sibling tab's mint wins the jar
    assert_response :success

    assert_difference -> { Session.count } do
      post session_url, headers: native,
        params: { authenticity_token: token, email_address: @user.email_address, password: "password123" }
    end
    assert_response :redirect
  end

  test "web sign-in still enforces the token" do
    get new_session_url
    token = form_token(session_path)

    cookies.to_hash.keys.each { |name| cookies.delete(name) }
    get new_session_url

    assert_no_difference -> { Session.count } do
      post session_url,
        params: { authenticity_token: token, email_address: @user.email_address, password: "password123" }
    rescue ActionController::InvalidAuthenticityToken
      # exception strategy surfaces directly depending on show_exceptions — both are a refusal
    end
  end
end
