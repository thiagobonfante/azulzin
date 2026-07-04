require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Azulzin
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Internationalization — pt-BR default, en-US supported (ADR 0006 / docs/i18n.md).
    # :en is loaded only as the fallback base; never offered as a UI choice.
    config.i18n.default_locale    = :"pt-BR"
    config.i18n.available_locales = [ :"pt-BR", :"en-US", :en ]
    config.i18n.fallbacks         = [ :en ]   # NEVER `true` (would fall back to pt-BR)

    # Brazil-first app: render/compute wall-clock time in São Paulo, store in UTC.
    # Without this the "hoje" default for a WhatsApp-captured transaction is off by one
    # for evening transactions (UTC rolls to tomorrow). See .plans/whats (Review P0-2).
    config.time_zone = "America/Sao_Paulo"
    config.active_record.default_timezone = :utc   # persist UTC, present in zone

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
