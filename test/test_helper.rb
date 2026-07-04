ENV["RAILS_ENV"] ||= "test"
# macOS libpq negotiates GSSAPI on connect, which is not fork-safe and segfaults the
# parallel test workers (pg connect_start). Disabling it is harmless (plain TCP to the
# local/Docker Postgres) and cross-platform. Must be set before any DB connection.
ENV["PGGSSENCMODE"] ||= "disable"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # The institution registry is loaded via test/fixtures/institutions.yml (generated
    # from config/institutions.yml), not a parallelize_setup DB call — the latter opened
    # a libpq connection inside forked workers and segfaulted on macOS.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # The allowlist gate (config.x.allowed_emails) is production-only, so it is unset
    # in test. Wrap assertions that exercise it in this helper. Safe under parallel
    # workers: they fork separate processes, and the ensure restores the prior value.
    def with_allowed_emails(emails)
      previous = Rails.configuration.x.allowed_emails
      Rails.configuration.x.allowed_emails = emails
      yield
    ensure
      Rails.configuration.x.allowed_emails = previous
    end
  end
end
