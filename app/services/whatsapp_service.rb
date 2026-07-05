# Rails → sidecar HTTP client (single number, no tenant path). Never raises: returns a
# symbol-keyed Hash, with { error: "..." } on failure, so a sidecar outage never breaks a
# request or job. See .plans/whats §3.4.
class WhatsappService
  class << self
    def base_url = ENV.fetch("WHATSAPP_SERVICE_URL", "http://localhost:3001")
    def token    = Whatsapp.service_token

    # target may be a bare number OR a full JID ("…@lid"/"…@c.us"). A JID is passed as
    # chat_id so the sidecar addresses it exactly — required for @lid contacts.
    def send_message(target, body)
      field = target.to_s.include?("@") ? :chat_id : :phone_number
      request(:post, "/messages", { field => target, message: body })
    end
    def initialize_session        = request(:post, "/session/initialize", {}, timeout: 30)
    def disconnect                = request(:delete, "/session")
    def status                    = request(:get, "/session/status")

    def health_check
      request(:get, "/health", timeout: 5)[:status] == "ok"
    rescue StandardError
      false
    end

    # Low-level HTTP. Public so tests can stub it; returns a symbol-keyed Hash.
    def request(method, path, body = nil, timeout: 10)
      uri = URI("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout

      req = build_request(method, uri, body)
      resp = http.request(req)
      parse(resp)
    rescue StandardError => e
      Rails.logger.error("WhatsappService #{method} #{path} failed: #{e.message}")
      { error: e.message }
    end

    private

    def build_request(method, uri, body)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"]  = "application/json"
      req.body = body.to_json if body
      req
    end

    def parse(resp)
      parsed = resp.body.present? ? (JSON.parse(resp.body, symbolize_names: true) rescue {}) : {}
      return parsed.merge(error: "sidecar #{resp.code}") unless resp.code.to_i.between?(200, 299)
      parsed.merge(error: nil)
    end
  end
end
