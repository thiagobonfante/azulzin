require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email_allowed? is unrestricted when no allowlist is configured" do
    assert User.email_allowed?("anyone@example.com")
  end

  test "email_allowed? honours the configured allowlist, ignoring case and spaces" do
    with_allowed_emails([ "me@example.com" ]) do
      assert     User.email_allowed?("  ME@Example.com ")
      assert_not User.email_allowed?("intruder@example.com")
    end
  end

  test "creating an off-allowlist user is blocked with a :not_allowed error" do
    with_allowed_emails([ "me@example.com" ]) do
      user = User.create(email_address: "intruder@example.com", password: "password123")
      assert_not user.persisted?
      assert user.errors.of_kind?(:email_address, :not_allowed)
    end
  end

  test "creating an allowlisted user succeeds" do
    with_allowed_emails([ "me@example.com" ]) do
      assert User.create(email_address: "me@example.com", password: "password123").persisted?
    end
  end

  test "phone is normalized to digits with the +55 country code" do
    assert_equal "5511912345678", User.new(phone: "(11) 91234-5678").phone
    assert_equal "5511912345678", User.new(phone: "5511912345678").phone   # already prefixed
  end

  test "the :profile context requires name and phone; sign-up does not" do
    user = User.new(email_address: "p@example.com", password: "password123")
    assert user.valid?                    # :create context — name/phone not required
    assert_not user.valid?(:profile)
    user.name = "Ana"
    user.phone = "11912345678"
    assert user.valid?(:profile)
  end

  test "update_as_profile persists name and normalized phone" do
    user = users(:confirmed)
    assert user.update_as_profile(name: "Ana", phone: "11912345678")
    assert_equal "Ana", user.reload.name
    assert_equal "5511912345678", user.phone
  end

  test "onboarded? flips after onboard!" do
    user = users(:confirmed)
    assert_not user.onboarded?
    user.onboard!
    assert user.reload.onboarded?
  end
end
