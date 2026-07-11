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

  test "sends the configured finance-vocabulary prompt to Groq" do
    media = FakeMedia.new("v.ogg", "audio/ogg")
    fake_resp = Struct.new(:code, :body).new("200", { text: "gastei 84,90" }.to_json)
    captured = :not_called
    Whatsapp::SttClient.stub(:api_key, "test-key") do
      Whatsapp::SttClient.stub(:post_multipart, ->(_b, _f, _ct, _lang, prompt) { captured = prompt; fake_resp }) do
        assert_equal "gastei 84,90", Whatsapp::SttClient.transcribe(media)
      end
    end
    assert_equal Rails.application.config.x.openrouter["transcription"]["prompt"], captured
    assert captured.present?, "the vocab-bias prompt must be configured and sent"
  end

  # WA-CAP-32b — Whisper on silence/noise echoes the vocab-bias prompt back as a confident,
  # parseable expense. Near-duplicates of any prompt sentence are flagged as no-speech.
  test "prompt_echo? flags near-duplicates of prompt sentences" do
    # The exact hallucination observed in exploratory testing (prompt says "Guardei"):
    assert Whatsapp::SttClient.prompt_echo?("Gastei R$ 200 na caixinha da poupança.")
    # Verbatim sentence and whole-prompt echoes:
    assert Whatsapp::SttClient.prompt_echo?("Guardei R$ 200 na caixinha da poupança.")
    assert Whatsapp::SttClient.prompt_echo?(Rails.application.config.x.openrouter["transcription"]["prompt"])
  end

  test "prompt_echo? passes real speech, blanks, and blank prompts" do
    refute Whatsapp::SttClient.prompt_echo?("gastei 84,90 no mercado hoje de manhã com a Marina")
    refute Whatsapp::SttClient.prompt_echo?("refri 13,90")
    refute Whatsapp::SttClient.prompt_echo?("")
    Whatsapp::SttClient.stub(:settings, {}) do
      refute Whatsapp::SttClient.prompt_echo?("Gastei R$ 200 na caixinha da poupança.")
    end
  end
end
