require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "verification mail is from the azulzin domain, not the placeholder" do
    mail = UserMailer.with(user: users(:unconfirmed)).email_verification
    assert_equal ["no-reply@azulzin.com.br"], mail.from
    assert_equal [users(:unconfirmed).email_address], mail.to
  end

  test "subject is pinned to pt-BR regardless of the recipient's stored locale" do
    ptbr    = UserMailer.with(user: users(:unconfirmed)).email_verification        # fixture locale: pt-BR
    enuser  = UserMailer.with(user: users(:english)).email_verification            # fixture locale: en-US (ignored while pinned)
    subject = I18n.t("user_mailer.email_verification.subject", locale: :"pt-BR")
    assert_equal subject, ptbr.subject
    assert_equal subject, enuser.subject                                           # en-US recipient still gets pt-BR
  end
end
