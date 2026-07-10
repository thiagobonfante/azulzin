require "test_helpers/e2e/pipeline_case"

# WEB-AUTH journeys that cross controller boundaries (.plans/e2e/05 §1) — the pieces the
# per-controller tests don't chain: a reset killing every live session end-to-end, and the
# allowlist refusing an EXISTING user at sign-in.
class E2E::WebAuthJourneysTest < E2E::PipelineCase
  test "password reset: email link → new password → every open session dies → new password signs in" do
    s = E2E::Scenario.build(:bare)
    2.times { s.owner.sessions.create! }   # a phone and a laptop, both signed in
    assert_equal 2, s.owner.sessions.count

    assert_enqueued_emails 1 do
      post passwords_path, params: { email_address: s.owner.email_address }
    end

    put password_path(s.owner.password_reset_token),
        params: { password: "nova-senha-123", password_confirmation: "nova-senha-123" }
    assert_redirected_to new_session_path

    assert_equal 0, s.owner.sessions.reload.count, "a reset must sign out every device"

    post session_path, params: { email_address: s.owner.email_address, password: E2E::Scenario::PASSWORD }
    assert_redirected_to new_session_path   # old password is dead

    post session_path, params: { email_address: s.owner.email_address, password: "nova-senha-123" }
    assert_equal 1, s.owner.sessions.reload.count, "the new password signs in"
  end

  test "allowlist gate blocks an EXISTING off-list user at sign-in, not just at signup" do
    s = E2E::Scenario.build(:bare)

    with_allowed_emails([ "someone-else@example.test" ]) do
      post session_path, params: { email_address: s.owner.email_address, password: E2E::Scenario::PASSWORD }
      assert_redirected_to new_session_path
      assert_equal 0, s.owner.sessions.count, "an off-list user must not get a session"
    end

    post session_path, params: { email_address: s.owner.email_address, password: E2E::Scenario::PASSWORD }
    assert_equal 1, s.owner.sessions.reload.count, "with the gate lifted the same user signs in"
  end
end
