require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy (Kamal/Thruster).
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Transactional email via Resend SMTP (verification + password reset). Secrets live in
  # encrypted credentials (resend.api_key); RAILS_MASTER_KEY must reach the deploy to decrypt.
  config.action_mailer.delivery_method       = :smtp
  config.action_mailer.perform_deliveries    = true
  config.action_mailer.raise_delivery_errors = true   # SMTP failures surface as failed Solid Queue jobs
  # Auth emails (verification + password reset) link into the product app, which
  # lives on the app subdomain — not the marketing apex. See config/routes.rb.
  config.action_mailer.default_url_options   = { host: "app.azulzin.com.br", protocol: "https" }
  config.action_mailer.smtp_settings = {
    address:   "smtp.resend.com",
    port:      465,
    tls:       true,
    user_name: "resend",
    password:  Rails.application.credentials.dig(:resend, :api_key)
  }

  # Locale fallbacks: end every chain at :en (matches config/application.rb).
  # NOT `true` — that would fall back to default_locale (pt-BR) and show Portuguese
  # to English users. See ADR 0006 / docs/i18n.md.
  config.i18n.fallbacks = [ :en ]

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Public marketing site (apex) vs. the product app (subdomain). Route constraints
  # and the marketing CTAs key off these to keep the two on separate hosts. See
  # config/routes.rb and app/helpers/application_helper.rb#app_url.
  config.x.marketing_host = "azulzin.com.br"
  config.x.app_host       = "app.azulzin.com.br"

  # Enable DNS rebinding protection: only serve the hosts we own.
  config.hosts = [ "azulzin.com.br", "www.azulzin.com.br", "app.azulzin.com.br" ]

  # Skip DNS rebinding protection for the health check (the Cloudflare tunnel probes it).
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
