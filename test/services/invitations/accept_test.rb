require "test_helper"

class Invitations::AcceptTest < ActiveSupport::TestCase
  setup do
    @owner   = users(:confirmed)
    @account = @owner.account
    @invitee = User.create!(email_address: "invitee@example.com", password: "password123")  # no account yet
  end

  def invite(email: "invitee@example.com")
    Invitation.issue!(account: @account, email: email, invited_by: @owner)
  end

  test "a fresh invited user (no own account) joins as a member" do
    inv = invite
    result = Invitations::Accept.call(user: @invitee, token: inv.token)
    assert result.ok
    assert_equal @account, @invitee.reload.account
    assert @invitee.account_membership.member?
    assert inv.reload.accepted_at
  end

  test "acceptance is idempotent — already a member + a still-pending token returns ok, no duplicate" do
    inv = invite                                            # issued while the invitee wasn't a member
    @account.memberships.create!(user: @invitee, role: "member")  # became a member another way
    assert_no_difference -> { @account.memberships.count } do
      assert Invitations::Accept.call(user: @invitee, token: inv.token).ok
    end
    assert inv.reload.pending?, "the early-return leaves the invite untouched"
  end

  test "an expired token is :invalid" do
    inv = invite
    inv.update_column(:expires_at, 1.day.ago)
    result = Invitations::Accept.call(user: @invitee, token: inv.token)
    assert_not result.ok
    assert_equal :invalid, result.error
  end

  test "a revoked (destroyed) token is :invalid" do
    token = invite.token
    Invitation.find_by(token: token).destroy!
    result = Invitations::Accept.call(user: @invitee, token: token)
    assert_not result.ok
    assert_equal :invalid, result.error
  end

  test "path (c): a solo + empty own account is folded in (destroyed) and the user joins" do
    Accounts::Bootstrap.call(@invitee)
    own = @invitee.account
    inv = invite
    result = Invitations::Accept.call(user: @invitee, token: inv.token)
    assert result.ok
    assert_equal @account, @invitee.reload.account
    assert_not Account.exists?(own.id), "the empty own account is destroyed"
  end

  test "an existing account WITH data refuses (:account_in_use) and changes nothing" do
    Accounts::Bootstrap.call(@invitee)
    own = @invitee.account
    own.bank_accounts.create!(institution: Institution.find_by(code: "260"))   # now non-empty
    inv = invite
    result = Invitations::Accept.call(user: @invitee, token: inv.token)
    assert_not result.ok
    assert_equal :account_in_use, result.error
    assert Account.exists?(own.id)
    assert_equal own, @invitee.reload.account
    assert inv.reload.pending?, "invitation stays pending for a retry"
  end

  test "accept fails :account_full when the account filled to 4 after the invite was sent" do
    inv = invite   # sent while there was room
    3.times do |i|
      u = User.create!(email_address: "m#{i}@example.com", password: "password123")
      @account.memberships.create!(user: u, role: "member")
    end
    assert_equal 4, @account.reload.members_count
    result = Invitations::Accept.call(user: @invitee, token: inv.token)
    assert_not result.ok
    assert_equal :account_full, result.error
    assert inv.reload.pending?
  end
end
