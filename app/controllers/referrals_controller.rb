# Refer-a-friend email (any member, not owner-gated — it touches no account data).
# No persistence: the recipient just signs up on their own; nothing to track or expire.
# ponytail: no Referral model/attribution — add one if referral analytics ever matter.
class ReferralsController < ApplicationController
  rate_limit to: 10, within: 1.hour, only: :create,
             with: -> { redirect_back fallback_location: dashboard_path, alert: t("shared.rate_limited") }

  MAX_PER_REQUEST = 10   # outbound-email endpoint: cap the batch, on top of the request rate limit

  def create
    emails = params.expect(referral: [ :email ])[:email].to_s.split(/[\s,;]+/).reject(&:blank?).uniq
    valid, invalid = emails.partition { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
    if invalid.any? || valid.empty?   # all-or-nothing: a typo sends no one anything
      alert = invalid.any? ? t(".invalid_emails", count: invalid.size, emails: invalid.join(", "))
                           : t(".invalid_email")
      redirect_back fallback_location: dashboard_path, alert: alert
    elsif valid.size > MAX_PER_REQUEST
      redirect_back fallback_location: dashboard_path, alert: t(".too_many", max: MAX_PER_REQUEST)
    else
      valid.each { |e| ReferralMailer.with(email: e, user: Current.user).invite.deliver_later }
      redirect_back fallback_location: dashboard_path,
                    notice: t(".sent", count: valid.size, emails: valid.join(", "))
    end
  end
end
