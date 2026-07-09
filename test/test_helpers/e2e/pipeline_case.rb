require "test_helper"
require_relative "helpers"

module E2E
  # Lane P: pipeline E2E. Inbound is the real webhook envelope with real bearer auth
  # (rack-level); outbound travels a real socket into FakeSidecarServer. Jobs drain
  # explicitly. See .plans/e2e/01 §1.
  class PipelineCase < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include E2E::Helpers
    include NotificationShapeAssertions

    setup do
      ENV["WHATSAPP_SERVICE_TOKEN"] = E2E::TOKEN
      fake_sidecar.reset!
      travel_to E2E.anchor
    end

    private

    def deliver_webhook(payload)
      post api_whatsapp_webhook_path, params: payload, as: :json,
           headers: { "Authorization" => "Bearer #{E2E::TOKEN}" }
      response
    end
  end
end
