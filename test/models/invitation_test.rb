require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @owner   = users(:confirmed)
    @account = @owner.account
  end

  test "issue! sets a token and a 7-day expiry and is pending" do
    inv = Invitation.issue!(account: @account, email: "a@example.com", invited_by: @owner)
    assert inv.token.present?
    assert inv.expires_at > 6.days.from_now
    assert inv.pending?
  end

  test "issue! refreshes an open invite in place (resend): same id, new token" do
    first = Invitation.issue!(account: @account, email: "a@example.com", invited_by: @owner)
    old_token = first.token
    second = Invitation.issue!(account: @account, email: "A@Example.com", invited_by: @owner)  # same, normalized
    assert_equal first.id, second.id
    assert_not_equal old_token, second.token
    assert_equal 1, @account.invitations.open.where(email: "a@example.com").count
  end

  test "the partial unique index forbids a second open invite for the same email" do
    Invitation.issue!(account: @account, email: "a@example.com", invited_by: @owner)
    dup = @account.invitations.build(email: "a@example.com", token: "t", expires_at: 1.day.from_now)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "under_cap counts members + pending invites for OTHER emails" do
    Invitation.issue!(account: @account, email: "a@example.com", invited_by: @owner)   # 1 member + 1
    Invitation.issue!(account: @account, email: "b@example.com", invited_by: @owner)   # + 1 = 3
    assert Invitation.issue!(account: @account, email: "c@example.com", invited_by: @owner).persisted?  # 4th slot
    assert_raises(ActiveRecord::RecordInvalid) do                                       # 1 + 3 pending = 4 → full
      Invitation.issue!(account: @account, email: "d@example.com", invited_by: @owner)
    end
  end

  test "an already-a-member email is rejected" do
    inv = @account.invitations.build(email: @owner.email_address)
    assert_not inv.valid?
    assert inv.errors.added?(:email, :already_member)
  end

  test "the prod allowlist gate refuses a non-allowlisted email at invite time" do
    with_allowed_emails([ "allowed@example.com" ]) do
      inv = @account.invitations.build(email: "notallowed@example.com")
      assert_not inv.valid?
      assert inv.errors.added?(:email, :not_allowed)
    end
  end
end
