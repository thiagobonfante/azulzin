require "test_helper"

class NotificationsHelperTest < ActionView::TestCase
  include MoneyHelper   # notification_message formats *_cents through brl at render time
  # 01 §1 / 03 §8: the banner templates from the payload snapshot alone — money formatted
  # at render time from integer cents — so a budget alert renders even after its category
  # is hard-deleted.
  test "a budget alert still renders after its category is gone" do
    user     = users(:confirmed)
    category = user.account.categories.create!(name: "Restaurantes", monthly_budget_cents: 60_000)
    row = Notification.record!(user: user, account: user.account, kind: "budget_warn",
                               subject: category, period_key: Date.new(2026, 7, 1),
                               payload: { category: "Restaurantes", spent_cents: 50_000,
                                          budget_cents: 60_000, left_cents: 10_000 })
    category.destroy!

    message = I18n.with_locale(:"pt-BR") { notification_message(row.reload) }
    assert_includes message, "Restaurantes"
    assert_match(/R\$\s*500,00/, message)
    assert_match(/R\$\s*600,00/, message)
    assert_match(/R\$\s*100,00/, message)
  end

  # 04 §3–4: a look-ahead-only week (Summaries::Build emits spent_cents: 0 when upcoming
  # bills exist) must never render "você gastou R$ 0,00" — the dashboard picks the
  # no-spend sibling key and drops the spent clause.
  test "a zero-spend weekly summary renders on the dashboard without the R$ 0,00 filler" do
    user = users(:confirmed)
    row = Notification.record!(user: user, account: user.account, kind: "weekly_summary",
                               period_key: Date.new(2026, 7, 6),
                               payload: { spent_cents: 0, sobra_cents: 41_000, other_cents: 0,
                                          top_categories: [],
                                          upcoming: [ { "name" => "Luz", "cents" => 18_240 } ] })

    message = I18n.with_locale(:"pt-BR") { notification_message(row) }
    assert_no_match(/R\$\s*0,00/, message)
    assert_match(/R\$\s*410,00/, message)

    # A week with real spend keeps the regular copy.
    spent = Notification.record!(user: user, account: user.account, kind: "weekly_summary",
                                 period_key: Date.new(2026, 7, 13),
                                 payload: { spent_cents: 92_000, sobra_cents: 41_000, other_cents: 0,
                                            top_categories: [ { "name" => "Mercado", "cents" => 92_000 } ],
                                            upcoming: [] })
    assert_match(/R\$\s*920,00/, I18n.with_locale(:"pt-BR") { notification_message(spent) })
  end
end
