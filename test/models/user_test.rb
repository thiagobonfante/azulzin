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
end
