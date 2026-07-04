require "test_helper"

class WhatsappServiceHealthCheckJobTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "caches liveness and broadcasts only when the up/down state flips" do
    # The test env uses a null_store, so swap in a real store for the duration to exercise
    # the previous-vs-current comparison.
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, store) do
      WhatsappService.stub(:health_check, -> { true }) do
        assert_broadcasts("whatsapp_service_status", 1) { WhatsappServiceHealthCheckJob.perform_now }
        assert_equal true, store.read(WhatsappServiceHealthCheckJob::CACHE_KEY)

        # Unchanged state → no second broadcast.
        assert_no_broadcasts("whatsapp_service_status") { WhatsappServiceHealthCheckJob.perform_now }
      end

      # Flip to down → broadcasts again.
      WhatsappService.stub(:health_check, -> { false }) do
        assert_broadcasts("whatsapp_service_status", 1) { WhatsappServiceHealthCheckJob.perform_now }
      end
    end
  end
end
