require "test_helper"

# The P0-1 identity guarantee: ingest only attributes money to a VERIFIED, UNIQUE number,
# and REFUSES an ambiguous match rather than guessing. See .plans/whats §3.3.
class UserWhatsappIdentityTest < ActiveSupport::TestCase
  test "wa_id_candidates toggles the Brazilian 9th digit both ways" do
    assert_equal %w[5511999998888 551199998888], User.wa_id_candidates("5511999998888@c.us")
    assert_equal %w[551199998888 5511999998888], User.wa_id_candidates("551199998888@c.us")
  end

  test "wa_id_candidates rejects too-short input" do
    assert_empty User.wa_id_candidates("123@c.us")
  end

  test "verified_for_wa resolves a verified, unique number" do
    u = users(:confirmed)
    u.update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current)
    assert_equal u, User.verified_for_wa("5511999998888@c.us")
  end

  test "verified_for_wa returns nil for an UNVERIFIED number" do
    u = users(:confirmed)
    u.update!(whatsapp_id: "5511999998888", phone_verified_at: nil)   # stored but not verified
    assert_nil User.verified_for_wa("5511999998888@c.us")
  end

  test "verified_for_wa REFUSES an ambiguous match (never attributes money to a guess)" do
    # Two verified users whose numbers collapse to the same candidate via the 9th-digit toggle.
    users(:confirmed).update!(whatsapp_id: "5511999998888", phone_verified_at: Time.current)
    users(:english).update!(whatsapp_id: "551199998888",   phone_verified_at: Time.current)
    assert_nil User.verified_for_wa("5511999998888@c.us")   # 0-or-≥2 → refuse
  end

  test "whatsapp_id is unique across accounts" do
    users(:confirmed).update!(whatsapp_id: "5511999990000", phone_verified_at: Time.current)
    dup = users(:english)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.update_columns(whatsapp_id: "5511999990000")   # skip validations → hit the DB unique index
    end
  end
end
