source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# OmniAuth social login (Phases 4-5)
gem "omniauth", "~> 2.1"
gem "omniauth-rails_csrf_protection", "~> 2.0"   # REQUIRED — closes CVE-2015-9284
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-facebook", "~> 10.0"

# Internationalization: pt-BR default, en-US supported (ADR 0006 / docs/i18n.md)
gem "rails-i18n", "~> 8.1"            # locale data: pluralization, date/number/currency
gem "http_accept_language", "~> 2.1" # guest browser-language negotiation (whitelisted)

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

# Document import (onboarding via extrato/fatura upload — .plans/auto)
gem "csv"                    # bundled gem on Ruby 3.4 — MUST be declared or `require "csv"` breaks
gem "pdf-reader", "~> 2.12"  # pure-Ruby PDF text extraction; no native deps, no shell-out

# Data export (up-tier F4 — .plans/up-tier/05): XLSX + PDF, all pure Ruby (no system deps)
gem "caxlsx", "~> 4.1"        # XLSX builder
gem "caxlsx_rails", "~> 0.6"  # registers the :xlsx Mime type for the download route
gem "prawn", "~> 2.5"         # PDF "extrato"
gem "prawn-table", "~> 0.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # i18n key linting: missing/unused translation keys (ADR 0006)
  gem "i18n-tasks", "~> 1.1"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview outgoing mail in the browser instead of sending it
  gem "letter_opener"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
