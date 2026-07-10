require "test_helpers/e2e/pipeline_case"

# WEB-GOAL-06: concluding a goal on render — the money must stop moving and the party must
# fire exactly once (.plans/e2e-t3 §C). Goals::Achieve auto-runs on the show render: the
# savings commitment is archived (it stops reserving/pulling money), and celebrated_at is
# stamped on the FIRST achieved render only (ADR 0012's idempotent celebration).
class E2E::WebGoalsAchieveTest < E2E::PipelineCase
  test "crossing the target archives the savings commitment and celebrates exactly once" do
    s = E2E::Scenario.build(:goal_active)
    sign_in_as s.owner
    goal = s.goal
    commitment = s.account.commitments.where(kind: "savings", goal: goal).sole
    assert_nil commitment.archived_at

    s.stash(goal.target_cents, on: Date.current)   # crosses the target

    get goal_path(goal)                            # achieve auto-runs on render
    assert_response :success

    goal.reload
    assert goal.achieved?
    assert_not_nil goal.achieved_at
    first_stamp = goal.celebrated_at
    assert_not_nil first_stamp, "the first achieved render stamps celebrated_at"
    assert_not_nil commitment.reload.archived_at, "the savings commitment stops pulling money"
    assert_includes response.body, I18n.t("goals.show.achieved_title", locale: :"pt-BR")

    get goal_path(goal)                            # second render: achieved, but no re-party
    assert_response :success
    assert_equal first_stamp, goal.reload.celebrated_at, "celebrated_at fires exactly once"
    assert_not_includes response.body, I18n.t("goals.show.achieved_title", locale: :"pt-BR"),
                        "the second render must not re-celebrate"
  end
end
