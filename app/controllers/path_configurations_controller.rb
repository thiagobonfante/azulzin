# Hotwire Native path configuration, served per platform so navigation behavior evolves
# without store releases (.plans/mobile/01 §4). Public: URL patterns only, no secrets.
class PathConfigurationsController < ApplicationController
  allow_unauthenticated_access

  # ponytail: one shared rule set for both platforms v1 — split per-platform when a rule
  # actually differs. "external": true is a custom property the shells consume (open in
  # SFSafariViewController / Custom Tab) — not a framework builtin.
  RULES = [
    # Later rules override earlier ones (Hotwire Native merges all matches top-down).
    { patterns: [ "/new$", "/edit$" ],
      properties: { context: "modal", pull_to_refresh_enabled: false } },
    # The goal wizard (new → draft → choose) is a multi-screen flow — push, not modal.
    { patterns: [ "^/goals/new$" ],
      properties: { context: "default", pull_to_refresh_enabled: false } },
    # Onboarding wizard back-steps behave under plain push navigation.
    { patterns: [ "^/onboarding" ],
      properties: { context: "default", pull_to_refresh_enabled: false } },
    # The export download itself (send_data GET, not /exports/new) leaves the webview.
    { patterns: [ "^/exports(\\?.*)?$" ],
      properties: { external: true } },
    # Sign-out lands back on sign-in with no back-stack into the app.
    { patterns: [ "/session$" ],
      properties: { presentation: "replace" } },
    # The chat thread is a Turbo Stream surface — the refresh gesture fights the composer.
    { patterns: [ "^/chat" ],
      properties: { pull_to_refresh_enabled: false } },
    # Tab roots refresh by pull.
    { patterns: [ "^/dashboard$", "^/transactions$", "^/goals$", "^/menu$" ],
      properties: { pull_to_refresh_enabled: true } }
  ].freeze

  def show
    expires_in 5.minutes, public: true
    render json: { settings: {}, rules: RULES }
  end
end
