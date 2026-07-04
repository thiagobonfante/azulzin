Rails.application.routes.draw do
  # In development/test everything is served on one origin (localhost), so the
  # host split is disabled. In production the marketing site lives on the apex
  # (azulzin.com.br) and the product app on the subdomain (app.azulzin.com.br).
  app_host       = Rails.application.config.x.app_host
  marketing_host = Rails.application.config.x.marketing_host
  on_app       = ->(req) { !Rails.env.production? || req.host == app_host }
  on_marketing = ->(req) { !Rails.env.production? || [ marketing_host, "www.#{marketing_host}" ].include?(req.host) }

  # Served on every host: the language switcher, health check, and robots.txt
  # (host-aware — see PagesController#robots).
  resource :locale, only: :update            # PATCH /locale
  get "up" => "rails/health#show", as: :rails_health_check
  get "/robots.txt" => "pages#robots"

  # ── Product app · app.azulzin.com.br ─────────────────────────────────────
  constraints(on_app) do
    resource :session
    resource :registration, only: %i[new create]
    resources :passwords, param: :token
    get  "email_verification/:token", to: "email_verifications#show",   as: :email_verification
    post "email_verification",        to: "email_verifications#create", as: :resend_email_verification

    # OAuth: Google only for now (Phase 5 broadens the constraint to include facebook).
    # The callback is a GET (Rails does not check CSRF on GET) — no skip_forgery_protection needed.
    get "auth/:provider/callback", to: "omniauth_callbacks#create",
        constraints: { provider: /google_oauth2/ }
    get "auth/failure", to: "omniauth_callbacks#failure"

    # ── Product app (authenticated) ──────────────────────────────────────
    get "dashboard", to: "dashboard#show", as: :dashboard

    # First-run setup wizard. `onboarding` (no step) resolves to the current step.
    get   "onboarding",       to: "onboarding#show", as: :onboarding
    get   "onboarding/:step", to: "onboarding#show", as: :onboarding_step,
          constraints: { step: /profile|accounts|cards/ }
    patch "onboarding/:step", to: "onboarding#update",
          constraints: { step: /profile|accounts|cards/ }

    resources :bank_accounts, only: %i[index create destroy]
    resources :credit_cards,  only: %i[index create destroy]

    # App-host landing. Signed-in users are sent straight to the product app.
    get "/", to: "pages#home", as: :app_root
  end

  # ── Public marketing site · azulzin.com.br ───────────────────────────────
  constraints(on_marketing) do
    root "pages#home"
  end
end
