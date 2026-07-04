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

  test "the profile step joins the country code with the national number into E.164" do
    user = users(:confirmed)
    assert user.update_as_profile(name: "Ana", country_code: "55", phone_national: "(45) 98811-5410")
    assert_equal "Ana", user.reload.name
    assert_equal "5545988115410", user.phone
  end

  test "a non-Brazilian country code is honoured; blank defaults to Brazil" do
    user = users(:confirmed)
    assert user.update_as_profile(name: "Ana", country_code: "351", phone_national: "912 345 678")
    assert_equal "351912345678", user.reload.phone
    assert user.update_as_profile(name: "Ana", country_code: "", phone_national: "45988115410")
    assert_equal "5545988115410", user.reload.phone
  end

  test "the :profile context requires name and phone; sign-up does not" do
    user = User.new(email_address: "p@example.com", password: "password123")
    assert user.valid?                    # :create context — name/phone not required
    assert_not user.valid?(:profile)
    user.name = "Ana"
    user.phone_national = "45988115410"   # composed to 55… by the :profile validation
    assert user.valid?(:profile)
  end

  test "onboarded? flips after onboard!" do
    user = users(:confirmed)
    assert_not user.onboarded?
    user.onboard!
    assert user.reload.onboarded?
  end
end
