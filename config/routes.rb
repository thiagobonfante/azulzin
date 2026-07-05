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

  # Sidecar → Rails WhatsApp webhook. Server-to-server (bearer token), so it sits OUTSIDE
  # the on_app/on_marketing host constraints. See .plans/whats §3.1.
  namespace :api do
    namespace :whatsapp do
      post "webhook", to: "webhooks#create"
    end
  end

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
          constraints: { step: /profile|accounts|incomes|cards/ }
    patch "onboarding/:step", to: "onboarding#update",
          constraints: { step: /profile|accounts|incomes|cards/ }

    resources :bank_accounts, only: %i[index create edit update destroy]  # edit/update: nickname, kind & balance
    resources :incomes,       only: %i[index create destroy]   # R1 — recurring income schedules
    resources :credit_cards,  only: %i[index create edit update destroy]  # edit/update: billing config (R2)

    # The monthly transactions hub (R3/R7/R8): index is the hub, new/create/edit power the
    # ledger's inline add + edit-in-place, and assign/confirm keep the guarded-transition inbox.
    resources :transactions, only: %i[index new create edit update destroy] do
      member do
        patch :assign    # pick an account/card for an unassigned row
        patch :confirm   # commit a pending/needs_* row → posted
      end
    end
    resources :transfers,  only: :create                         # R5 — single-row transfer between accounts

    # R10/R11 — recurring commitments and their computed occurrences.
    resources :commitments, only: %i[index show create update destroy]
    resources :commitment_occurrences, only: [] do
      member do
        patch :pay
        patch :unpay
      end
    end
    resources :categories, only: %i[index create update destroy] do  # R6 — user-owned spend categories
      post :restore, on: :collection                                  # re-seed the locale defaults
    end

    # Admin area (privileged, over all users' data). A normal in-app surface, so it lives
    # inside the on_app host constraint — unlike the server-to-server webhook. See 07 §7.2.
    namespace :admin do
      resource :whatsapp_connection, only: :show do
        post   :reconnect
        delete :logout
      end
      resources :whatsapp_messages, only: %i[index show]   # inbound audit
    end

    # App-host landing. Signed-in users are sent straight to the product app.
    get "/", to: "pages#home", as: :app_root
  end

  # ── Public marketing site · azulzin.com.br ───────────────────────────────
  constraints(on_marketing) do
    root "pages#home"
  end
end
