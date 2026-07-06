# Invite email in the INVITER's locale (spine D4): the recipient may not have a user/locale yet,
# and a family shares a language. Callers pass user: Current.user in .with(...) so the existing
# ApplicationMailer#set_locale picks it up automatically when the en-US pin is lifted (pt-BR today).
class InvitationMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    @url = accept_invitation_url(token: @invitation.token)
    mail to: @invitation.email,
         subject: default_i18n_subject(inviter: @invitation.invited_by&.name,
                                       account: @invitation.account.name)
  end
end
