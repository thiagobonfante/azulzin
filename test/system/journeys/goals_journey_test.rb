require "test_helpers/e2e/browser_case"

# WEB-GOAL P0 browser residue (.plans/e2e/05 §5): the create form → 3 plan cards → choose a
# template from a click → the goal goes active, with the savings_account/source pickers driven the
# real way (the plan math itself is owned by goals_flow_test.rb — ~30 request tests).
class JourneysGoalsTest < E2E::BrowserCase
  test "create a purchase goal, choose recomendado, and activate it" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)

    visit new_goal_path
    fill_in "goal_name", with: "Carro novo"
    fill_in "goal_target_reais", with: "20000"
    find("select[name='goal[target_date]'] option[value='2027-12-01']").select_option   # ~18mo out → feasible
    click_button I18n.t("goals.form.submit")

    # the draft screen shows the three plan cards
    assert_text I18n.t("goals.plans.labels.leve")
    assert_text I18n.t("goals.plans.labels.recomendado")
    assert_text I18n.t("goals.plans.labels.acelerado")

    # recomendado is the pre-checked template; pick the savings_account + source and activate
    pick_account "bank_account_id", s.savings_account.display_name
    pick_account "source_bank_account_id", s.itau.display_name
    click_button I18n.t("goals.confirm.activate")
    assert_text I18n.t("goals.choose.activated")   # wait for the redirect before touching the DB

    goal = s.account.goals.sole
    assert goal.active?, "choosing a template and clicking Ativar activates the goal"
    assert_equal s.savings_account.id, goal.bank_account_id
    assert_equal "recomendado", goal.plan["template"]
    assert s.account.commitments.where(kind: "savings", goal: goal).exists?
  end

  private

  # Drive a shared/account_select picker (hidden field written by the institution-select
  # stimulus controller) — click its button, then the option whose text is the account name.
  def pick_account(field_name, account_label)
    picker = find(:xpath, "//*[@data-controller='institution-select'][.//input[@name='#{field_name}']]")
    within picker do
      find("[data-institution-select-target='button']").click
      find("li[data-institution-select-target='option']", text: account_label).click
      # Wait for the picker to commit: the button display copies the picked label AND the hidden
      # field is set. Asserting the display (a retrying matcher) closes the panel-race before the
      # next action — the classic system-test flake.
      assert_selector "[data-institution-select-target='button']", text: account_label
    end
  end
end
