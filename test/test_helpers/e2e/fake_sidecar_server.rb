require "capybara"

module E2E
  # In-process stand-in for the WhatsApp sidecar's HTTP surface (whatsapp-sidecar/src/app.js,
  # mirrored by fake.js). Boots lazily once per test worker on an ephemeral port and points
  # WHATSAPP_SERVICE_URL at itself, so WhatsappService's real Net::HTTP requests — bearer
  # header, JSON body, response parsing — travel a real socket. Lane C (contract smokes
  # against the real node fake.js) pins parity. See .plans/e2e/01 §2.
  class FakeSidecarServer
    Message = Struct.new(:target, :body, :at, keyword_init: true)

    class << self
      def instance
        @instance ||= new.tap(&:boot!)
      end
    end

    attr_reader :port

    def boot!
      server = Capybara::Server.new(rack_app)
      server.boot
      @port = server.port
      ENV["WHATSAPP_SERVICE_URL"] = "http://127.0.0.1:#{@port}"
    end

    def reset!
      @mutex.synchronize { @messages.clear }
      @mode = :connected
    end

    def messages = @mutex.synchronize { @messages.dup }

    # Outbound targets are a JID ("…@c.us") or a bare phone; match either form.
    def messages_to(target)
      digits = target.to_s[/\d+/]
      messages.select { |m| m.target == target || (digits && m.target.to_s[/\d+/] == digits) }
    end

    def not_connected! = @mode = :not_connected  # POST /messages → 409, like a dropped session
    def down!          = @mode = :down           # every request → 500, like a dead sidecar

    private

    def initialize
      @messages = []
      @mutex = Mutex.new
      @mode = :connected
    end

    def rack_app
      fake = self
      ->(env) { fake.send(:handle, Rack::Request.new(env)) }
    end

    def handle(req)
      return [ 500, {}, [ "sidecar down" ] ] if @mode == :down

      case [ req.request_method, req.path ]
      when [ "GET", "/health" ]
        json({ status: "ok", state: state_name })
      when [ "GET", "/session/status" ], [ "POST", "/session/initialize" ]
        json({ status: state_name.downcase })
      when [ "DELETE", "/session" ]
        json({ status: "logged_out" })
      when [ "POST", "/messages" ]
        handle_send(req)
      else
        [ 404, {}, [ "" ] ]
      end
    end

    def handle_send(req)
      return [ 401, {}, [ "" ] ] unless authorized?(req)
      return json({ error: "not_connected" }, status: 409) if @mode == :not_connected

      params = JSON.parse(req.body.read)
      target = params["chat_id"] || params["phone_number"]
      id = @mutex.synchronize do
        @messages << Message.new(target: target, body: params["message"], at: Time.current)
        @messages.size
      end
      json({ success: true, messageId: "fake_out_#{id}" })
    end

    def authorized?(req)
      token = req.get_header("HTTP_AUTHORIZATION").to_s.split(" ").last
      ActiveSupport::SecurityUtils.secure_compare(token.to_s, Whatsapp.service_token.to_s)
    end

    def state_name = @mode == :connected ? "CONNECTED" : "DISCONNECTED"

    def json(payload, status: 200)
      [ status, { "content-type" => "application/json" }, [ payload.to_json ] ]
    end
  end
end
