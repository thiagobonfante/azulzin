require "test_helper"

# WEB-REF-01 — refer-a-friend: valid email queues the invite, junk queues nothing, and the
# email body is pinned (golden pt-BR copy + signup URL). The WhatsApp path is a plain
# wa.me share link in the layout — nothing server-side to test.
class ReferralsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Thiago", onboarded_at: Time.current)
    sign_in_as(@user)
  end

  test "a valid email queues the referral invite" do
    assert_enqueued_emails 1 do
      post referral_url, params: { referral: { email: "amigo@example.com" } }
    end
    assert_redirected_to dashboard_url
    assert_equal I18n.t("referrals.create.sent", count: 1, emails: "amigo@example.com"), flash[:notice]
  end

  test "a comma-separated list queues one invite per unique address" do
    assert_enqueued_emails 2 do
      post referral_url, params: { referral: { email: "amigo@example.com, bia@example.com; amigo@example.com" } }
    end
    assert_equal I18n.t("referrals.create.sent", count: 2, emails: "amigo@example.com, bia@example.com"),
                 flash[:notice]
  end

  test "one bad address in the list means nothing is sent" do
    assert_no_enqueued_emails do
      post referral_url, params: { referral: { email: "amigo@example.com, not-an-email" } }
    end
    assert_equal I18n.t("referrals.create.invalid_emails", count: 1, emails: "not-an-email"), flash[:alert]
  end

  test "a blank submit queues nothing" do
    assert_no_enqueued_emails do
      post referral_url, params: { referral: { email: " , " } }
    end
    assert_equal I18n.t("referrals.create.invalid_email"), flash[:alert]
  end

  test "more than the per-request cap queues nothing" do
    list = (1..11).map { |i| "amigo#{i}@example.com" }.join(",")
    assert_no_enqueued_emails do
      post referral_url, params: { referral: { email: list } }
    end
    assert_equal I18n.t("referrals.create.too_many", max: 10), flash[:alert]
  end

  # multiple: true silently renames the input to referral[email][] unless the name is pinned —
  # the mismatch 400s and Turbo swallows it, so the form looks dead. Pin the rendered name.
  test "the invite form posts the scalar param the controller expects" do
    get dashboard_url
    assert_select "form[action=?]", referral_path do
      assert_select "input[name=?][multiple]", "referral[email]"
    end
  end

  test "the invite email carries the pinned pt-BR copy and the signup link" do
    mail = ReferralMailer.with(email: "amigo@example.com", user: @user).invite
    assert_equal [ "amigo@example.com" ], mail.to
    assert_equal I18n.t("referral_mailer.invite.subject", inviter: "Thiago"), mail.subject
    body = mail.text_part.body.to_s
    assert_includes body, I18n.t("referral_mailer.invite.headline", inviter: "Thiago")
    assert_includes body, I18n.t("referral_mailer.invite.intro")
    assert_includes body, new_registration_path
  end
end
