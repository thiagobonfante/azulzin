require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:confirmed)
    @owner.update!(name: "Owner", phone: "5511912345678", onboarded_at: Time.current)
    @account = @owner.account
    @member_user = User.create!(email_address: "member@example.com", password: "password123", name: "Bia")
    @membership  = @account.memberships.create!(user: @member_user, role: "member")
  end

  test "owner removes a member: membership + their sessions gone, they get a fresh empty account" do
    @member_user.sessions.create!   # a live session elsewhere
    sign_in_as(@owner)
    assert_difference -> { @account.memberships.count }, -1 do
      delete account_member_url(@membership), as: :turbo_stream
    end
    assert_response :success
    assert_not AccountMembership.exists?(@membership.id)
    assert_equal 0, @member_user.sessions.count, "signed out everywhere"
    assert_not_equal @account, @member_user.reload.account, "minted a fresh own account"
  end

  # The inline-guard regression (an `or return` inversion would let this through and 500).
  test "a non-owner removing another member changes NOTHING" do
    third = User.create!(email_address: "c@example.com", password: "password123")
    third_membership = @account.memberships.create!(user: third, role: "member")
    sign_in_as(@member_user)
    assert_no_difference -> { @account.memberships.count } do
      delete account_member_url(third_membership)
    end
    assert AccountMembership.exists?(third_membership.id)
    assert_redirected_to account_path
  end

  test "a non-owner cannot promote (roles unchanged)" do
    sign_in_as(@member_user)
    patch promote_account_member_url(@membership)
    assert_equal @owner, @account.memberships.find_by(role: "owner").user
    assert @membership.reload.member?
    assert_redirected_to account_path
  end

  test "owner promotes a member: demote-then-promote leaves exactly one owner" do
    sign_in_as(@owner)
    patch promote_account_member_url(@membership)
    assert @membership.reload.owner?
    assert @owner.account_membership.reload.member?
    assert_equal 1, @account.memberships.where(role: "owner").count
    assert_redirected_to account_path
  end

  test "self-leave: membership gone, the current session survives, fresh own account" do
    sign_in_as(@member_user)
    own_session = Current.session
    delete account_member_url(@membership)
    assert_not AccountMembership.exists?(@membership.id)
    assert Session.exists?(own_session.id), "the leaver stays signed in"
    assert_not_equal @account, @member_user.reload.account
    assert_redirected_to dashboard_path
  end

  test "the owner cannot leave without transferring ownership first" do
    sign_in_as(@owner)
    delete account_member_url(@owner.account_membership)
    assert AccountMembership.exists?(@owner.account_membership.id)
    assert_redirected_to account_path
  end
end
