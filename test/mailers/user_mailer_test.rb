require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "verification mail is from the azulzin domain, not the placeholder" do
    mail = UserMailer.with(user: users(:unconfirmed)).email_verification
    assert_equal ["no-reply@azulzin.com.br"], mail.from
    assert_equal [users(:unconfirmed).email_address], mail.to
  end

  test "subject renders in the recipient's locale (pt-BR vs en-US)" do
    pt = UserMailer.with(user: users(:unconfirmed)).email_verification            # fixture locale: pt-BR
    en = UserMailer.with(user: users(:english)).email_verification                # fixture locale: en-US
    assert_equal I18n.t("user_mailer.email_verification.subject", locale: :"pt-BR"), pt.subject
    assert_equal I18n.t("user_mailer.email_verification.subject", locale: :"en-US"), en.subject
    refute_equal pt.subject, en.subject
  end
end
