require "test_helpers/e2e/browser_case"

# WEB-TX-02 / WEB-CARD-01 / WEB-DASH-01: the screens show the pack's frozen numbers to the
# centavo, and every surface agrees (.plans/e2e/05 §2, §3, §8).
class JourneysMoneyScreensTest < E2E::BrowserCase
  test "transactions hub: every MonthSummary term equals the calibration" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)

    visit transactions_path

    assert_text brl(500_000)   # entradas (salary received day 5)
    assert_text brl(208_721)   # sobra = 5.000,00 − 2.612,79 − 300,00 (guardado)
    assert_text brl(261_279)   # saídas month-to-date
    assert_text brl(30_000)    # guardado do mês
  end

  test "dashboard tiles: derived balances exact and consistent with the WA answers" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)

    visit dashboard_path

    assert_text brl(250_000)   # Itaú derived (anchored AFTER history, so derived == stored)
    assert_text brl(520_000)   # Caixinha
  end

  test "card tile: usado and disponível match the billing engine exactly" do
    s = E2E::Scenario.build(:cards_billing)
    used = s.nubank_card.used_cents
    assert used.positive?, "the pack must hold limit (purchases + reserved parcels)"

    sign_in_via_ui(s.owner, password: E2E::Scenario::PASSWORD)
    visit credit_cards_path

    assert_text brl(used)
    assert_text brl(650_000 - used)   # disponível = limit − used, no drift between tiles
  end
end
