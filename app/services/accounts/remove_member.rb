# Remove (or self-leave) a member (spine D8). keep_session: pass Current.session on SELF-leave
# so the leaver stays signed in and can be redirected into their fresh account; owner-initiated
# removal passes nothing and the removed member is signed out everywhere. One transaction: a
# crash can never leave an account-less user (Current.account nil → 500s).
module Accounts
  class RemoveMember
    def self.call(membership, keep_session: nil)
      raise ArgumentError, "cannot remove the owner" if membership.owner?
      user = membership.user
      ApplicationRecord.transaction do
        user.sessions.where.not(id: keep_session&.id).destroy_all
        membership.destroy!                       # counter_cache decrements members_count
        Bootstrap.call(user)                      # fresh empty own Account + owner membership
      end
    end
  end
end
