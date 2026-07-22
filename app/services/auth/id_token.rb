require "net/http"

module Auth
  # Native-SSO trust boundary (.plans/mobile/10): the shells obtain a Google/Apple ID
  # token via the platform SDKs (webview OAuth is blocked by Google) and POST it to
  # TokenSessionsController; this verifies signature (provider JWKS), exp, iss and aud
  # before any of it is believed. Returns the payload hash, or nil for anything invalid.
  module IdToken
    APPLE_BUNDLE_ID = "br.com.azulzin.app"   # native aud; a web Services ID would join it

    PROVIDERS = {
      # Android tokens carry the WEB client id as aud (Credential Manager's
      # serverClientId); iOS tokens carry the iOS client id.
      "google_oauth2" => {
        jwks: "https://www.googleapis.com/oauth2/v3/certs",
        iss:  [ "https://accounts.google.com", "accounts.google.com" ],
        auds: -> { [ Rails.application.credentials.dig(:google, :client_id),
                     Rails.application.credentials.dig(:google, :ios_client_id) ].compact }
      },
      "apple" => {
        jwks: "https://appleid.apple.com/auth/keys",
        iss:  [ "https://appleid.apple.com" ],
        auds: -> { [ APPLE_BUNDLE_ID ] }
      }
    }.freeze

    def self.verify(token, provider:)
      config = PROVIDERS.fetch(provider)
      auds   = config[:auds].call
      return nil if token.blank? || auds.empty?   # unconfigured provider → refuse, don't 500

      payload, _header = JWT.decode(
        token, nil, true,
        algorithms: [ "RS256" ],
        jwks: ->(options) { jwks_for(config[:jwks], invalidate: options[:invalidate] || options[:kid_not_found]) },
        iss: config[:iss], verify_iss: true,
        aud: auds, verify_aud: true
      )
      payload
    rescue JWT::DecodeError
      nil
    end

    # Provider signing keys rotate rarely; cache them and refetch once when a token
    # arrives signed by an unknown kid (the jwt gem retries the loader with invalidate).
    def self.jwks_for(url, invalidate: false)
      cache_key = "auth/jwks/#{url}"
      Rails.cache.delete(cache_key) if invalidate
      Rails.cache.fetch(cache_key, expires_in: 12.hours) do
        JSON.parse(Net::HTTP.get(URI(url)), symbolize_names: true)
      end
    end
  end
end
