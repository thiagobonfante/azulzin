require "test_helper"

# The attribution partial (spine D7): invisible on solo accounts, a creator chip / full sentence
# once the account has more than one member. Rendered directly so the guard is exercised in
# isolation from any page.
class AttributionPartialTest < ActionView::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @txn = @account.transactions.create!(amount_cents: 100, occurred_on: Date.current,
             status: "posted", direction: "expense", created_by: @user)
    Current.session = @user.sessions.create!
  end

  teardown { Current.reset }

  def add_second_member
    other = User.create!(email_address: "m@example.com", password: "password123", name: "Bia")
    @account.memberships.create!(user: other, role: "member")   # members_count -> 2
    other
  end

  test "renders nothing on a solo account" do
    render partial: "shared/attribution", locals: { record: @txn }
    assert_equal "", rendered.strip
  end

  test "renders a creator chip on a multi-member account" do
    add_second_member
    render partial: "shared/attribution", locals: { record: @txn }
    assert_match @user.display_name.first.upcase, rendered
    assert_match I18n.t("shared.attribution.by", name: @user.display_name), rendered
  end

  test "a nil created_by renders removed_user (LGPD null-out)" do
    add_second_member
    @txn.update_column(:created_by_id, nil)
    render partial: "shared/attribution", locals: { record: @txn.reload }
    assert_match I18n.t("shared.attribution.removed_user"), rendered
  end

  test "full mode names the editor only when it differs from the creator" do
    editor = add_second_member
    @txn.update_column(:updated_by_id, editor.id)   # bypass the Attributable callback (it stamps Current.user)
    render partial: "shared/attribution", locals: { record: @txn.reload, full: true }
    assert_match I18n.t("shared.attribution.by", name: @user.display_name), rendered
    assert_match I18n.t("shared.attribution.edited_by", name: editor.display_name), rendered
  end
end
