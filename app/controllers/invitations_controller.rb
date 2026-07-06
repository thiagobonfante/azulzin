# Owner-only invite create/revoke (spine D4/D9). create goes through Invitation.issue! (a
# build/save path would raise RecordNotUnique on the "resend = resubmit the same email" gesture);
# the rate_limit stays (outbound-email endpoint); the mailer gets user: Current.user for locale.
class InvitationsController < ApplicationController
  include AccountOwnership
  layout "app"
  before_action :require_owner!
  rate_limit to: 10, within: 1.hour, only: :create,
             with: -> { redirect_to account_path, alert: t("shared.rate_limited") }

  def create
    @invitation = Invitation.issue!(account: Current.account, email: invitation_params[:email],
                                    invited_by: Current.user)
    InvitationMailer.with(invitation: @invitation, user: Current.user).invite.deliver_later
    respond_to do |format|
      format.turbo_stream   # append row, clear errors, reset form
      format.html { redirect_to account_path, notice: t(".sent", email: @invitation.email) }
    end
  rescue ActiveRecord::RecordInvalid => e
    @invitation = e.record
    respond_to do |format|
      format.turbo_stream { render :create, status: :unprocessable_entity }   # errors div
      format.html { redirect_to account_path, alert: e.record.errors.full_messages.to_sentence }
    end
  end

  def destroy   # revoke
    @invitation = Current.account.invitations.find(params[:id])
    @invitation.destroy!
    respond_to do |format|
      format.turbo_stream            # remove dom_id(@invitation)
      format.html { redirect_to account_path, notice: t(".revoked"), status: :see_other }
    end
  end

  private
    def invitation_params = params.expect(invitation: %i[email])
end
