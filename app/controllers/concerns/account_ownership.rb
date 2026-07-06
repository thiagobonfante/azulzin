# Owner gate (spine D9). Owner-only surface = invitations create/revoke, member removal,
# ownership transfer, account rename/delete. Everything else is equal for every member.
#
# CONTRACT: returns true for the owner; sets the redirect and returns false otherwise. As a
# before_action the redirect halts the chain by itself; INLINE call sites MUST use
# `return unless require_owner!` — never `require_owner! or return`, which inverts the gate
# (owner short-circuits, non-owner falls through into the guarded action and commits the side
# effect before DoubleRenderError fires).
module AccountOwnership
  extend ActiveSupport::Concern

  private
    def require_owner!
      return true if Current.user.account_membership.owner?
      redirect_to account_path, alert: t("accounts.not_owner")
      false
    end
end
