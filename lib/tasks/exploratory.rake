# Numbered seeds for manual exploratory testing (docs/exploratory-tests.md).
require_relative "../exploratory_seeds"

namespace :exploratory do
  desc "List every exploratory seed (test-N@azulzin.dev per scenario)"
  task list: :environment do
    ExploratorySeeds::SCENARIOS.each do |n, s|
      puts format("  %2d  %-16s %s", n, s[:slug], s[:title])
    end
    puts "\nSeed one: bin/rails \"exploratory:seed[4]\" · all: bin/rails exploratory:seed_all"
  end

  desc "Seed scenario N as test-N@azulzin.dev (wipes + recreates). Usage: exploratory:seed[4]"
  task :seed, [ :n ] => :environment do |_t, args|
    dev_only!
    abort "Usage: bin/rails \"exploratory:seed[N]\" (see exploratory:list)" unless args[:n]
    ExploratorySeeds.run(args[:n])
  end

  desc "Seed ALL exploratory scenarios (test-1 … test-#{ExploratorySeeds::SCENARIOS.keys.max})"
  task seed_all: :environment do
    dev_only!
    ExploratorySeeds::SCENARIOS.each_key { |n| ExploratorySeeds.run(n) }
  end

  desc "Wipe scenario N's users and data. Usage: exploratory:wipe[4]"
  task :wipe, [ :n ] => :environment do |_t, args|
    dev_only!
    abort "Usage: bin/rails \"exploratory:wipe[N]\"" unless args[:n]
    ExploratorySeeds.wipe(Integer(args[:n]))
    puts "✔ wiped scenario #{args[:n]}"
  end

  def dev_only!
    abort "exploratory:* only runs in development." unless Rails.env.development?
  end
end
