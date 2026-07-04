require "test_helper"

class InstitutionTest < ActiveSupport::TestCase
  test "registry is seeded, with OTHER present and ordered last" do
    assert Institution.exists?(code: "260")
    assert_equal "000", Institution.other.code
    assert_equal Institution.other, Institution.ordered.last
  end

  test "load_registry! is idempotent" do
    assert_no_difference "Institution.count" do
      Institution.load_registry!
    end
  end

  test "display_name is the bank name, but localized for OTHER" do
    assert_equal "Nubank", Institution.find_by(code: "260").display_name
    assert_equal I18n.t("institutions.other"), Institution.other.display_name
  end

  test "dark_text? true for light brand fills, false for dark ones" do
    assert     Institution.find_by(code: "001").dark_text?   # Banco do Brasil yellow
    assert     Institution.find_by(code: "536").dark_text?   # Neon cyan
    assert_not Institution.find_by(code: "260").dark_text?   # Nubank purple
  end

  test "for_accounts and for_cards return position-ordered institutions" do
    accounts = Institution.for_accounts
    assert_includes accounts, Institution.find_by(code: "260")
    assert_equal accounts.map(&:position), accounts.map(&:position).sort
  end

  test "logo_path is derived from the presence of a vendored svg" do
    assert_equal "institutions/260.svg", Institution.find_by(code: "260").logo_path
    assert_nil Institution.find_by(code: "001").logo_path
  end
end
