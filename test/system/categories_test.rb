require "application_system_test_case"

# The category budget field is a cents money input like every other — typed digits are
# centavos (3c8c1db); this pins the mask on the edit form (it was missed in the first sweep).
class CategoriesTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    @category = @user.account.categories.create!(name: "Pets")

    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password123"
    click_button I18n.t("sessions.new.submit")
    assert_text I18n.t("dashboard.greeting", name: "Ana")
  end

  test "the budget field masks typed digits as centavos and posts the exact cents" do
    visit categories_path
    find("a[href='#{edit_category_path(@category)}']").click

    within "##{dom_id(@category)}" do
      budget = find_field I18n.t("categories.budget")
      budget.send_keys "20000"
      assert_equal "200,00", budget.value
      click_button I18n.t("categories.save")
      # Wait on the streamed row swap (edit form closes) before touching the DB.
      assert_selector "a[href='#{edit_category_path(@category)}']"
    end
    assert_equal 20_000, @category.reload.monthly_budget_cents
  end
end
