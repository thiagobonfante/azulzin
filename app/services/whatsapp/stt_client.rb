module Whatsapp
  # Speech-to-text for WhatsApp voice notes (ogg/opus), via Groq's OpenAI-compatible
  # /audio/transcriptions endpoint. OpenRouter is NOT used for STT — it is a chat gateway
  # with no transcription route (Review P1-1). Verify the model slug against Groq's live
  # list before relying on it. Class methods so it's trivially stubbed in tests.
  module SttClient
    ENDPOINT     = "https://api.groq.com/openai/v1/audio/transcriptions".freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    class Error < StandardError; end

    module_function

    # config/openrouter.yml → transcription: (Groq). ENV overrides; default is a safe fallback.
    def settings = (Rails.application.config.x.openrouter["transcription"] || {})
    def model    = ENV["GROQ_STT_MODEL"].presence || settings["model"].presence || "whisper-large-v3-turbo"
    def api_key  = Rails.application.credentials.dig(:groq, :api_key).presence || ENV["GROQ_API_KEY"].presence

    # media: an ActiveStorage attachment (the ogg/opus voice note). Returns the transcript.
    def transcribe(media, language: nil)
      raise Error, "missing Groq API key" if api_key.blank?
      language ||= settings["language"].presence || "pt"
      bytes    = media.download
      filename = media.filename.to_s.presence || "audio.ogg"
      content_type = media.content_type.presence || "audio/ogg"
      parse(post_multipart(bytes, filename, content_type, language))
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
      # Transport failures become OUR Error so the job's STT retry→degrade path owns them —
      # a raw timeout would ride the job's generic Net retry_on and dead-end silently
      # (stuck "processing", no reply) once those attempts exhaust.
      raise Error, "transport: #{e.class}: #{e.message}"
    end

    def post_multipart(bytes, filename, content_type, language)
      uri  = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req.set_form([
        [ "file", StringIO.new(bytes), { filename: filename, content_type: content_type } ],
        [ "model", model ],
        [ "language", language ],
        [ "response_format", "json" ],
        [ "temperature", "0" ]
      ], "multipart/form-data")
      http.request(req)
    end

    def parse(resp)
      raise Error, "Groq STT #{resp.code}: #{resp.body.to_s[0, 200]}" unless resp.code.to_i.between?(200, 299)
      JSON.parse(resp.body)["text"].to_s.strip
    end
  end
end
