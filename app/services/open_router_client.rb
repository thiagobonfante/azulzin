# Thin client over openrouter.ai's chat/completions gateway, used for text extraction
# (Phase 1/2) and vision receipt extraction (Phase 4). STT is NOT here — it runs against
# Groq directly (SttClient). Strict json_schema output, timeouts, bounded retries, typed
# errors, and usage capture. Injectable so the AI boundary is stubbed in tests.
#
# Privacy: no `X-Data-Policy: allow-free-models` header (financial PII); configure
# zero-data-retention + logging-off in the OpenRouter account. See .plans/whats §4.1.
class OpenRouterClient
  BASE_URL     = "https://openrouter.ai/api/v1".freeze
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 60
  MAX_RETRIES  = 2

  class Error < StandardError; end
  class RateLimited < Error; end
  class Unauthorized < Error; end

  Result = Struct.new(:content, :parsed, :usage, :raw, keyword_init: true)

  def initialize(task:, http: nil)
    @cfg  = Rails.application.config.x.openrouter.fetch(task.to_s)
    @http = http   # inject a responder for tests: #call(uri, headers, body_hash) => Result-ish
  end

  # messages: OpenAI-style array. schema: { name:, schema: } for strict JSON output.
  def chat(messages:, schema: nil, **overrides)
    payload = {
      model:       overrides[:model] || @cfg["model"],
      messages:    messages,
      temperature: overrides.fetch(:temperature, @cfg["temperature"] || 0),
      max_tokens:  overrides[:max_tokens] || @cfg["max_tokens"]
    }
    if schema
      payload[:response_format] = {
        type: "json_schema",
        json_schema: { name: schema[:name], strict: true, schema: schema[:schema] }
      }
      payload[:provider] = { require_parameters: true }   # block silent json_object downgrade
    end
    post("/chat/completions", payload)
  end

  private

  def api_key
    Rails.application.credentials.dig(:openrouter, :key).presence || ENV["OPENROUTER_API_KEY"].presence
  end

  def headers
    {
      "Authorization" => "Bearer #{api_key}",
      "Content-Type"  => "application/json",
      "HTTP-Referer"  => ENV.fetch("APP_URL", "https://app.azulzin.com.br"),
      "X-Title"       => "azulzin"
    }
  end

  def post(path, payload, attempt: 0)
    raise Unauthorized, "missing OpenRouter API key" if api_key.blank?
    return @http.call(path, headers, payload) if @http   # test seam

    uri  = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    resp = http.post(uri.path, payload.to_json, headers)
    handle(resp)
  rescue RateLimited, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    attempt += 1
    raise e if attempt > MAX_RETRIES
    sleep(2**attempt + rand)
    retry
  end

  def handle(resp)
    case resp.code.to_i
    when 200..299
      body    = JSON.parse(resp.body)
      content = body.dig("choices", 0, "message", "content") || body["text"]
      raise Error, "empty completion" if content.blank?
      parsed = (JSON.parse(content) rescue nil)
      Result.new(content: content, parsed: parsed, usage: body["usage"], raw: body)
    when 401 then raise Unauthorized, "unauthorized"
    when 402 then raise Error, "insufficient credits"
    when 429 then raise RateLimited, "rate limited"
    else raise Error, "OpenRouter #{resp.code}: #{resp.body.to_s[0, 300]}"
    end
  end
end
