module Notifications
  # FCM HTTP v1 sender (.plans/mobile/04 §1): one integration delivers Android natively
  # and relays to APNs for iOS. Plain Net::HTTP; the OAuth token is a hand-minted
  # service-account JWT assertion (jwt gem is already in the bundle) — same protocol the
  # googleauth gem speaks, without its dependency chain. Never raises upward: a push
  # outage falls back to the WhatsApp branch in Deliver.
  class PushSender
    SCOPE        = "https://www.googleapis.com/auth/firebase.messaging".freeze
    TOKEN_URL    = "https://oauth2.googleapis.com/token".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class << self
      # Test seam: a callable that receives the FCM message payload and returns
      # { ok: } / { prune: } — swapped in by the E2E/unit harness; nil in production.
      attr_accessor :transport

      def credentials = Rails.application.credentials.firebase
      def configured? = transport.present? || credentials.present?

      # Sends to every device of the user; prunes tokens FCM reports dead. True when at
      # least one device accepted — false lets Deliver fall back to WhatsApp.
      def deliver(user:, title:, body:, url:)
        sent = false
        user.push_devices.find_each do |device|
          result = post(message(device.token, title, body, url))
          if result[:ok]
            sent = true
          elsif result[:prune]
            device.destroy
          end
        end
        sent
      end

      # Quiet, discreet payload: title/body render on lock screens; data.url is the
      # tap-through deep link the shells route.
      def message(token, title, body, url)
        { message: { token: token,
                     notification: { title: title, body: body },
                     data: { url: url.to_s } } }
      end

      def post(payload)
        return transport.call(payload) if transport
        uri  = URI("https://fcm.googleapis.com/v1/projects/#{credentials[:project_id]}/messages:send")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                       "Authorization" => "Bearer #{access_token}")
        req.body = payload.to_json
        parse(http.request(req))
      rescue StandardError => e
        Rails.logger.error("PushSender failed: #{e.class}: #{e.message}")
        { ok: false }
      end

      # UNREGISTERED (dead token) and INVALID_ARGUMENT (malformed token) prune the row.
      def parse(resp)
        return { ok: true } if resp.code.to_i.between?(200, 299)
        prune = resp.body.to_s.match?(/UNREGISTERED|INVALID_ARGUMENT/)
        Rails.logger.warn("PushSender FCM #{resp.code}: #{resp.body.to_s[0, 200]}")
        { ok: false, prune: prune }
      end

      # Service-account OAuth: RS256 JWT assertion → bearer token, cached until expiry.
      def access_token
        return @access_token if @access_token && @access_token_expires_at&.future?
        now = Time.current.to_i
        assertion = JWT.encode(
          { iss: credentials[:client_email], scope: SCOPE, aud: TOKEN_URL,
            iat: now, exp: now + 3600 },
          OpenSSL::PKey::RSA.new(credentials[:private_key]), "RS256")
        resp = Net::HTTP.post_form(URI(TOKEN_URL),
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion)
        data = JSON.parse(resp.body)
        @access_token_expires_at = Time.current + data.fetch("expires_in", 3600).to_i - 60
        @access_token = data.fetch("access_token")
      end
    end
  end
end
