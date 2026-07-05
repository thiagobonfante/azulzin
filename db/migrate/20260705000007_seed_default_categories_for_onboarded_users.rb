# One-off backfill (01 §8): seed the 12 default categories for users who onboarded before
# this phase existed (the current allowlist). Idempotent — Categories::SeedDefaults uses
# find_or_create_by! per name, so a re-run adds nothing.
class SeedDefaultCategoriesForOnboardedUsers < ActiveRecord::Migration[8.1]
  def up
    User.where.not(onboarded_at: nil).find_each do |user|
      Categories::SeedDefaults.call(user)
    end
  end

  def down
    # Categories are user data — leave them on rollback.
  end
end
