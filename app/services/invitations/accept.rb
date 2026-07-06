# Bind whoever completes authentication holding the invite token to the inviting account
# (spine D4 — token possession, not email equality, so it survives Google-with-a-different-email).
# Never blocks sign-in: failures return a Result and the caller flashes it; the invitation stays
# pending so a revisit can retry once the owner frees a seat.
module Invitations
  class Accept
    Result = Data.define(:ok, :error)   # error ∈ nil | :invalid | :account_full | :account_in_use

    def self.call(user:, token:)
      invitation = Invitation.find_by(token:)
      return Result.new(false, :invalid) unless invitation&.pending?
      account = invitation.account
      return Result.new(true, nil) if account.memberships.exists?(user: user)   # idempotent re-click

      result = nil
      ApplicationRecord.transaction do
        own = user.account_membership&.account
        if own && !solo_and_empty?(own, user)
          result = Result.new(false, :account_in_use)
          raise ActiveRecord::Rollback
        end
        if own                              # solo + empty → fold it in (D4)
          user.account_membership.destroy!
          own.destroy!
        end
        account.with_lock do                # D1 app-level cap, serialized by the row lock
          # Re-check under the lock: two holders of the same forwarded token racing here must not
          # both join — the winner stamps accepted_at, the loser sees it and bails as :invalid.
          unless invitation.reload.pending?
            result = Result.new(false, :invalid)
            raise ActiveRecord::Rollback
          end
          account.memberships.create!(user: user, role: :member)   # counter_cache → CHECK(≤4)
          invitation.update!(accepted_at: Time.current)
          result = Result.new(true, nil)
        end
      end
      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid   # validation or CHECK
      Result.new(false, :account_full)
    end

    def self.solo_and_empty?(account, user)
      account.members_count == 1 &&
        %i[bank_accounts credit_cards transactions commitments incomes document_imports]
          .all? { |assoc| account.public_send(assoc).none? }
    end
  end
end
