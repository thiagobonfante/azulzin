require "test_helpers/e2e/pipeline_case"

# Phase 1 gate: pack calibrations hold at mid-month, month-start and month-end (the packs
# are evergreen — relative to the traveled now). See .plans/e2e/06 Phase 1.
class E2E::ScenarioPacksTest < E2E::PipelineCase
  ANCHORS = {
    mid_month:   E2E.anchor,
    month_start: Time.utc(2026, 5, 1, 15, 0),
    month_end:   Time.utc(2026, 5, 31, 15, 0)
  }.freeze

  ANCHORS.each do |label, anchor|
    test "history_calibrated holds its bands and median at #{label}" do
      travel_to anchor
      s = E2E::Scenario.build(:history_calibrated)   # verify_calibration! raises if bands drift

      assert_equal 132_500, spent(s, "Mercado")
      assert_equal 64_780,  spent(s, "Restaurantes")
      assert_equal 36_000,  spent(s, "Transporte")
      assert_equal 27_999,  spent(s, "Lazer")
      assert_equal 250_000, s.itau.reload.derived_balance_cents
      assert_equal 520_000, s.caixinha.reload.derived_balance_cents
    end

    test "reminders_due yields due/overdue material at #{label}" do
      travel_to anchor
      s = E2E::Scenario.build(:reminders_due)
      events = Reminders::Scan.call(s.account, from: Date.current, to: Date.current + 1)
      kinds = events.map { |e| e[:kind] }
      assert_includes kinds, "bill_due",     "Condomínio due tomorrow must be scanned"
      assert_includes kinds, "bill_overdue", "Luz (2 days late) must be inside the 3-day grace"
      names = events.map { |e| e[:payload][:name] }
      assert_not_includes names, "Água", "5 days late is outside the overdue grace"
    end
  end

  test "cards_billing straddles the closing date" do
    s = E2E::Scenario.build(:cards_billing)
    on_close  = s.account.transactions.find_by!(merchant: "Na Data de Corte")
    after     = s.account.transactions.find_by!(merchant: "Depois do Corte")
    assert_equal on_close.billing_month >> 1, after.billing_month,
                 "a purchase the day after closing must land one fatura later"
  end

  test "couple: two verified members, one shared ledger, unique identities" do
    s = E2E::Scenario.build(:couple)
    assert_equal 2, s.account.members_count
    assert s.owner.phone_verified? && s.partner.phone_verified?
    assert_not_equal s.jid(s.owner), s.jid(s.partner)
    assert_not_equal s.owner.email_address, s.partner.email_address
  end

  test "scenarios are isolated: two builds never share rows" do
    a = E2E::Scenario.build(:solo_basic)
    b = E2E::Scenario.build(:solo_basic)
    assert_not_equal a.account.id, b.account.id
    assert_empty a.account.transactions.where(id: b.account.transactions.select(:id))
    assert_not_equal a.owner.phone, b.owner.phone
  end

  private

  def spent(scenario, category_name)
    Budgets::Actuals.for(scenario.account, Date.current.beginning_of_month)
                    .fetch(scenario.category(category_name).id, 0)
  end
end
