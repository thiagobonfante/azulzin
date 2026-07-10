require "test_helper"

class Whatsapp::SttClientTest < ActiveSupport::TestCase
  FakeMedia = Struct.new(:filename, :content_type) do
    def download = "fake-ogg-bytes"
  end

  # A raw Net timeout would ride the job's generic Net retry_on and dead-end silently once
  # exhausted; wrapped as SttClient::Error it rides the STT retry→degrade path instead
  # (friendly reply + failed message — e2e-t3 §A2 follow-up).
  test "transport timeouts surface as SttClient::Error" do
    media = FakeMedia.new("v.ogg", "audio/ogg")
    Whatsapp::SttClient.stub(:api_key, "test-key") do
      [ Net::ReadTimeout.new, Net::OpenTimeout.new, Errno::ECONNRESET.new ].each do |transport_error|
        Whatsapp::SttClient.stub(:post_multipart, ->(*) { raise transport_error }) do
          err = assert_raises(Whatsapp::SttClient::Error) { Whatsapp::SttClient.transcribe(media) }
          assert_match(/transport/, err.message)
        end
      end
    end
  end
end
