# Joins a user to their (only) account, carrying role (spine D1). Carries the app's FIRST
# counter_cache — it exists for the members_count CHECK constraint (the atomic cap), not for
# UI. app-level validation gives the friendly error; the CHECK is the true guard.
class AccountMembership < ApplicationRecord
  belongs_to :account, counter_cache: :members_count
  belongs_to :user
  enum :role, { owner: "owner", member: "member" }, validate: true  # string-backed, app convention

  validate :account_has_room, on: :create

  private
    def account_has_room
      return unless account
      errors.add(:base, :account_full) if account.memberships.count >= Account::MAX_MEMBERS
    end
end
