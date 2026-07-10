require "test_helpers/e2e/pipeline_case"

# MU web journeys (.plans/e2e/05 §6). Lane P (integration): the enforcement layers and the
# LGPD destroy cascade are data/authorization truths — asserted through the real controllers
# with real cookie auth, no browser. (The wired danger-zone button / invite-accept UI is the
# only browser-only residue; demoted to Lane P per the 06 §2 budget lever — vetoable.)
class E2E::MultiUserWebTest < E2E::PipelineCase
  # MU-08 — the LGPD delete cascade: owner deletes the account → EVERY member User is erased,
  # neither can sign back in, all financial rows are gone. The roadmap's named-scariest #1.
  test "deleting the account erases every member User and all its rows (LGPD cascade)" do
    s = E2E::Scenario.build(:couple)
    s.expense(merchant: "Compra", category: "Outros", instrument: s.itau, cents: 5_000, on: Date.current)
    owner, partner = s.owner, s.partner
    partner.sessions.create!   # an open session on the member's device

    sign_in_as owner
    delete account_path
    assert_redirected_to new_session_path

    assert_not User.exists?(owner.id), "the owner User is erased"
    assert_not User.exists?(partner.id), "the member User is erased too — nobody can sign back in"
    assert_not Account.exists?(s.account.id)
    assert_equal 0, Session.where(user_id: [ owner.id, partner.id ]).count, "every session died"
    assert_equal 0, Transaction.where(account_id: s.account.id).count, "financial rows gone"
  end

  # MU-01 — a fresh user with an empty solo account accepts an invite: their solo account folds
  # away and they become a member of the inviting family account.
  test "accepting an invite folds the invitee's empty solo account into the family" do
    s = E2E::Scenario.build(:solo_basic)
    invitee = fresh_user
    old_account_id = invitee.account.id
    invite = Invitation.issue!(account: s.account, email: invitee.email_address, invited_by: s.owner)

    sign_in_as invitee
    post confirm_invitation_path(invite.token)
    assert_redirected_to dashboard_path

    assert_equal s.account.id, invitee.reload.account.id, "the invitee joined the family account"
    assert_not Account.exists?(old_account_id), "the empty solo account was folded away"
    assert_equal 2, s.account.reload.members_count
    assert invite.reload.accepted_at.present?
  end

  # MU-03 — the member cap (MAX_MEMBERS=4), enforced at BOTH the invite layer (validation) and
  # the accept layer (the with_lock re-check + the CHECK(≤4) constraint).
  test "the member cap refuses a new invite and a racing accept once full" do
    s = E2E::Scenario.build(:couple)                       # owner + 1 member = 2
    invite = Invitation.issue!(account: s.account, email: "invitee@example.test", invited_by: s.owner)
    2.times { s.account.add_member!(loose_user) }          # fill to 4 → account is now full
    assert_equal 4, s.account.reload.members_count

    late = Invitation.new(account: s.account, email: "fifth@example.test", invited_by: s.owner)
    assert_not late.valid?, "the invite layer refuses a 5th"
    assert_includes late.errors.details[:base].map { |d| d[:error] }, :cap_reached

    result = Invitations::Accept.call(user: fresh_user, token: invite.token)
    assert_not result.ok, "the accept layer refuses a token that now overflows the cap"
    assert_equal :account_full, result.error
    assert_equal 4, s.account.reload.members_count, "no 5th membership was created"
  end

  # MU-05 — owner removes a member: they are signed out EVERYWHERE, a fresh solo account is
  # minted, and their attribution on the family's old rows survives.
  test "removing a member signs them out everywhere and mints a fresh solo account" do
    s = E2E::Scenario.build(:couple)
    member = s.partner
    member_session = member.sessions.create!
    txn = s.expense(merchant: "Do Rafael", category: "Outros", instrument: s.itau,
                    cents: 5_000, on: Date.current, by: member)
    old_display = member.display_name

    sign_in_as s.owner
    delete account_member_path(member.account_membership)

    assert_equal 0, Session.where(id: member_session.id).count, "the member is signed out everywhere"
    assert_not_equal s.account.id, member.reload.account.id, "a fresh solo account is minted"
    assert s.account.transactions.exists?(txn.id), "their row survives on the family ledger"
    assert_equal old_display, txn.reload.created_by.display_name, "attribution display name intact"
  end

  private

  # A confirmed user with an empty solo account — a valid invitee (solo_and_empty? holds).
  def fresh_user = E2E::Scenario.build(:bare).owner

  # A confirmed user with NO membership yet — safe to add_member! (the unique user_id index
  # forbids adding a user who already owns an account).
  def loose_user
    n = E2E::Seq.next
    User.create!(email_address: "loose-#{n}@example.test", password: E2E::Scenario::PASSWORD,
                 name: "Loose #{n}", phone: format("5511%09d", 800_000_000 + n), confirmed_at: Time.current)
  end
end
