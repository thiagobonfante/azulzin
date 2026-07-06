# Swap roles owner <=> member (spine D9). ORDER MATTERS: the one-owner partial unique
# (index_account_memberships_one_owner) is checked per-statement, so promote-first ALWAYS
# raises. Demote first, promote second, one transaction — if the promote fails, the demote
# rolls back and the account is never left ownerless (there is no admin tooling to repair that).
module Accounts
  class TransferOwnership
    def self.call(from:, to:)
      raise ArgumentError, "not the owner"     unless from.owner?
      raise ArgumentError, "different account" unless from.account_id == to.account_id
      ApplicationRecord.transaction do
        from.update!(role: "member")
        to.update!(role: "owner")
      end
    end
  end
end
