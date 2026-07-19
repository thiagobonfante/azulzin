# Refer-a-friend email in the SENDER's locale (same rationale as InvitationMailer): the
# recipient has no user yet, and friends usually share a language. Callers pass
# user: Current.user so ApplicationMailer#set_locale picks it up when the pt-BR pin lifts.
class ReferralMailer < ApplicationMailer
  def invite
    @inviter = params[:user]
    @url = new_registration_url
    mail to: params[:email], subject: default_i18n_subject(inviter: @inviter.display_name)
  end
end
