# The shared-account settings page (members, invites, rename, danger zone). show is open to
# every member; update/destroy are owner-only (spine D9). See doc 06.
class AccountsController < ApplicationController
  include AccountOwnership
  layout "app"
  before_action :require_onboarding, only: :show
  before_action :require_owner!, only: %i[update destroy]

  def show
    @account     = Current.account
    @memberships = @account.memberships.includes(:user).order(:created_at)
    @invitations = @account.invitations.pending.order(:created_at)
  end

  def update   # rename only
    if Current.account.update(params.expect(account: [ :name ]))
      redirect_to account_path, notice: t(".renamed")
    else
      redirect_to account_path, alert: Current.account.errors.full_messages.to_sentence
    end
  end

  def destroy  # LGPD cascade — the ordered dependent: :destroy chain lives on Account (D8)
    account = Current.account
    ApplicationRecord.transaction do
      # "Todos os dados" includes the logins: EVERY member User dies with the account
      # (sessions + OAuth identities cascade off User), so nobody can sign back in. A
      # surviving User would otherwise mint a fresh solo account on the next sign-in.
      members = account.users.to_a
      account.destroy!
      members.each(&:destroy!)
    end
    cookies.delete(:session_id)   # own session row is already gone with the rest
    redirect_to new_session_path, notice: t(".deleted"), status: :see_other
  end
end
