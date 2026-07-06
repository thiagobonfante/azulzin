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
      # EVERY member's sessions die with the account, not just the deleting owner's: a surviving
      # spouse's live session would otherwise resolve Current.account to nil and 500 on every
      # page. Signed out, their next sign-in mints a fresh solo account (doc 06 §2).
      account.users.find_each { |member| member.sessions.destroy_all }
      account.destroy!
    end
    cookies.delete(:session_id)   # own session row is already gone with the rest
    redirect_to new_session_path, notice: t(".deleted"), status: :see_other
  end
end
