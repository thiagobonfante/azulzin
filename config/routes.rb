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
    # PWA (install-only): manifest + service worker, served on the app host.
    get "manifest.json"     => "rails/pwa#manifest",       as: :pwa_manifest
    get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

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

    # Native SSO (.plans/mobile/10): the shells verify identity via the platform SDKs
    # (Google blocks OAuth inside webviews) and the page POSTs the ID token here.
    post "auth/:provider/token", to: "token_sessions#create", as: :token_session,
         constraints: { provider: /google_oauth2|apple/ }

    # Hotwire Native path configuration (.plans/mobile/01 §4) — public, per platform.
    get "configurations/:platform", to: "path_configurations#show", as: :path_configuration,
        constraints: { platform: /ios_v1|android_v1/ }, defaults: { format: :json }

    # ── Product app (authenticated) ──────────────────────────────────────
    get "dashboard", to: "dashboard#show", as: :dashboard

    # Native tab targets (.plans/mobile/01 §3): the in-app chat thread and the "Mais" menu.
    get "chat", to: "chat#show", as: :chat
    resources :chat_messages, only: :create   # the composer POST (.plans/mobile/08 §3)
    get "menu", to: "menu#show", as: :menu

    # First-run setup wizard. `onboarding` (no step) resolves to the current step.
    get   "onboarding",       to: "onboarding#show", as: :onboarding
    get   "onboarding/:step", to: "onboarding#show", as: :onboarding_step,
          constraints: { step: /profile|accounts|incomes|cards/ }
    patch "onboarding/:step", to: "onboarding#update",
          constraints: { step: /profile|accounts|incomes|cards/ }
    patch "onboarding/skip", to: "onboarding#skip", as: :onboarding_skip   # invited member: one click into the shared app

    # Onboarding via document upload (.plans/auto). No index/show — the status frame renders
    # inside the accounts step and the accounts index; review is ONE page over all imports.
    resources :document_imports, only: %i[create destroy] do
      member do
        post :unlock # decrypt a password-protected PDF in-request (P1-3); password never persisted
      end
      collection do
        get  :status   # Turbo Frame polled by import_status_controller (2s)
        get  :review   # one review form over all the user's extracted imports
        post :apply    # Imports::Apply — checked pids create records; discard[pid] rejects
      end
    end

    resources :bank_accounts, only: %i[index create edit update destroy]  # edit/update: nickname, kind & balance
    resources :incomes,       only: %i[index create edit update destroy] do  # R1 — recurring income schedules
      member { patch :receive }   # mark this month's expected deposit as received (hub card)
    end
    resources :credit_cards,  only: %i[index create edit update destroy]  # edit/update: billing config (R2)

    # The monthly transactions hub (R3/R7/R8): index is the hub, new/create/edit power the
    # ledger's inline add + edit-in-place, and update/confirm keep the guarded-transition inbox.
    resources :transactions, only: %i[index new create edit update destroy] do
      collection do
        get :recent      # "Hoje" — purchase-date view of today + yesterday (.plans/today-expenses)
      end
      member do
        patch :confirm   # commit a pending/needs_* row → posted (saves review edits first)
        get   :receipt   # up-tier F5 — authenticated, account-scoped receipt bytes (proxied)
      end
    end
    resources :transfers,  only: :create                         # R5 — single-row transfer between accounts

    # up-tier F4 — data export: new is the form, index the sync download (send_data).
    resources :exports, only: %i[new index]

    # R10/R11 — recurring commitments and their computed occurrences.
    resources :commitments, only: %i[index show create update destroy] do
      member do
        patch :settle      # early payoff of a debit installment plan
        patch :pay_batch   # pay several selected parcels at once
      end
    end
    resources :commitment_occurrences, only: [] do
      member do
        patch :pay
        patch :unpay
      end
    end
    resources :categories, only: %i[index create edit update destroy] do  # R6 — account-owned spend categories
      post :restore, on: :collection                                  # re-seed the locale defaults
      get  :suggest, on: :collection                                  # merchant-memory preselect (LLM-free)
      get  :suggest_budget, on: :member                               # 3-month-median budget pre-fill (up-tier 03 §3)
      post :backfill,         on: :collection                         # categorize history (1/day cap)
      post :backfill_undo,    on: :collection                         # revert the last run
      post :backfill_dismiss, on: :collection                         # hide the banner, keep the categories
    end

    # Metas — financial goals (.plans/goals). draft → choose (recompute + guarded activate) → active.
    # No goal_checks dismiss route: the notification spine owns dashboard-alert dismissal (06 §2).
    resources :goals, only: %i[index new create show update destroy] do
      member do
        patch :choose    # template=leve|recomendado|acelerado (+ bank_account_id, source_bank_account_id)
        patch :caps      # Diagnóstico orçamento sliders — caps={category_id: cents}, draft only
        patch :abandon
        patch :replan    # mode=extend|hold_date — re-derived server-side (round 4)
        post  :contribute  # speed-up extra transfer, bounded by the re-derived sobra (round 3 P3)
      end
    end

    # Notification spine (.plans/up-tier 01): dashboard alerts (dismiss only — rows are
    # scanner-created) and the per-member "Avisos" preferences screen.
    resources :notifications, only: [] do
      member { patch :dismiss }
    end
    resource :notification_preferences, only: %i[show update]
    # Native push registration (.plans/mobile/04 §3): the shells' bridge POSTs the FCM
    # token here through the webview session.
    resources :push_devices, only: :create
    # Share-to-app receipts (.plans/mobile/05): the shells POST the shared file here.
    resources :captures, only: :create

    # Shared account: settings page (members, invites, rename, danger zone). Owner-gated
    # actions live in AccountOwnership#require_owner! (.plans/multi-user, D9).
    resource :account, only: %i[show update destroy] do
      resources :invitations, only: %i[create destroy]                # /account/invitations
      resources :members,     only: %i[index destroy] do
        patch :promote, on: :member                                   # ownership transfer (D9)
      end
    end
    # Public invite acceptance (D4). POST = signed-in confirm (never auto-accept on GET, doc 02 §2.2).
    get  "invites/:token", to: "invitation_acceptances#show",   as: :accept_invitation
    post "invites/:token", to: "invitation_acceptances#create", as: :confirm_invitation

    # Refer-a-friend: outbound "come try azulzin" email (recipient creates their OWN account —
    # unlike Invitation, which joins yours). Stateless, so no model behind it.
    resource :referral, only: :create

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
