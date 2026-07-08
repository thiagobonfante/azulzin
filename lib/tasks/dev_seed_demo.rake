# Seeds the fictional "Família Andrade" demo household (Marina owner + Rafael member) sharing
# one account, with 4 trailing full months of evergreen, deterministic history. The heavy
# lifting lives in DemoSeed.run — dev and prod share it byte-for-byte and differ only in the
# environment guard below, so the prod demo logs in with the SAME credentials once its emails
# are on the allowlist (config.x.allowed_emails in config/environments/production.rb).
#
# Usage: bin/rails dev:seed_demo [PASSWORD=demo1234]
#        RAILS_ENV=production bin/rails prod:seed_demo [PASSWORD=demo1234]
require_relative "../demo_seed"

namespace :dev do
  desc "Seed dev data for the fictional Família Andrade demo (wipes + recreates both users)"
  task seed_demo: :environment do
    abort "dev:seed_demo only runs in development." unless Rails.env.development?
    DemoSeed.run(password: ENV.fetch("PASSWORD", DemoSeed::DEFAULT_PASSWORD))
  end
end

namespace :prod do
  desc "Seed the Família Andrade demo household in PRODUCTION (wipes + recreates both users)"
  task seed_demo: :environment do
    abort "prod:seed_demo only runs in production." unless Rails.env.production?
    DemoSeed.run(password: ENV.fetch("PASSWORD", DemoSeed::DEFAULT_PASSWORD))
  end
end
