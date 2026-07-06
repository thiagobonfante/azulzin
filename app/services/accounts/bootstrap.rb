# Mint a user's own solo account + owner membership (spine D1). Called from non-invite signup
# paths (registrations#create, from_omniauth create-branch) and the ensure_membership_for
# invariant fallback (doc 02 §3). NO category seeding here — that stays in User#onboard!
# (doc 03), so Bootstrap is safe to call for a user who never finishes onboarding.
module Accounts
  class Bootstrap
    def self.call(user)
      ApplicationRecord.transaction do
        name = user.name.presence || user.email_address.to_s.split("@").first
        account = Account.create!(name: name)
        account.memberships.create!(user: user, role: "owner")
        account
      end
    end
  end
end
