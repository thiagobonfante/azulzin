# Member removal / self-leave / ownership transfer (spine D9). index exists per the spine's
# route list but the page is accounts#show. Removal mechanics = Accounts::RemoveMember (doc 01).
class MembersController < ApplicationController
  include AccountOwnership
  layout "app"

  def index = redirect_to(account_path)

  # Two personas share destroy: an owner removes someone else; a non-owner removes themself
  # ("leave"). Inline guard contract (concern §): `return unless require_owner!` — NEVER
  # `or return`, which lets a non-owner's direct POST run the service before the render blows up.
  def destroy
    membership = Current.account.memberships.includes(:user).find(params[:id])
    if membership.user == Current.user
      return redirect_to account_path, alert: t(".owner_cannot_leave") if membership.owner?
      # keep_session: the self-leaver stays signed in and lands on their fresh account
      Accounts::RemoveMember.call(membership, keep_session: Current.session)
      redirect_to dashboard_path, notice: t(".left"), status: :see_other
    else
      return unless require_owner!
      @membership = membership
      Accounts::RemoveMember.call(membership)   # all sessions destroyed: signed out everywhere
      respond_to do |format|
        format.turbo_stream            # remove dom_id(membership) + refresh the count badge
        format.html { redirect_to account_path, notice: t(".removed") }
      end
    end
  end

  def promote
    return unless require_owner!
    membership = Current.account.memberships.find(params[:id])
    Accounts::TransferOwnership.call(from: Current.user.account_membership, to: membership)
    redirect_to account_path, notice: t(".promoted", name: membership.user.display_name)
  end
end
