require "application_system_test_case"
require_relative "helpers"

module E2E
  # Lane B: browser E2E. The browser drives the real Puma server; WA injections POST the
  # webhook over a real socket to that same server. Assert server-rendered content only —
  # Chrome's clock is NOT traveled. See .plans/e2e/01 §1, §5.
  class BrowserCase < ApplicationSystemTestCase
    include ActiveJob::TestHelper
    include E2E::Helpers
    include NotificationShapeAssertions

    setup do
      ENV["WHATSAPP_SERVICE_TOKEN"] = E2E::TOKEN
      fake_sidecar.reset!
      travel_to E2E.anchor
    end

    # System tests can't use the cookie-based SessionTestHelper — sign in through the UI.
    def sign_in_via_ui(user, password:)
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button I18n.t("sessions.new.submit")
      assert_text I18n.t("dashboard.greeting", name: user.name.split.first)
    end

    private

    def deliver_webhook(payload)
      server = Capybara.current_session.server
      raise "visit a page before wa_inject (Capybara server not booted yet)" unless server
      uri = URI("http://#{server.host}:#{server.port}/api/whatsapp/webhook")
      res = Net::HTTP.post(uri, payload.to_json,
                           "Content-Type" => "application/json",
                           "Authorization" => "Bearer #{E2E::TOKEN}")
      raise "webhook returned HTTP #{res.code}" unless res.code.to_i.between?(200, 299)
      res
    end
  end
end
