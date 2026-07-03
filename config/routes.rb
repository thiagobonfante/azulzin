Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  get  "email_verification/:token", to: "email_verifications#show",   as: :email_verification
  post "email_verification",        to: "email_verifications#create", as: :resend_email_verification
  resource :locale, only: :update            # PATCH /locale

  # OAuth: Google only for now (Phase 5 broadens the constraint to include facebook).
  # The callback is a GET (Rails does not check CSRF on GET) — no skip_forgery_protection needed.
  get "auth/:provider/callback", to: "omniauth_callbacks#create",
      constraints: { provider: /google_oauth2/ }
  get "auth/failure", to: "omniauth_callbacks#failure"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "pages#home"
end
