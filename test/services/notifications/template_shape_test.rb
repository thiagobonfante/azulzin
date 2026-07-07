require "test_helper"

# The Phase 3 shape gate (up-tier 08 §9): EVERY whatsapp.replies.notifications.* template
# renders in BOTH locales from a realistic scanner payload — through the exact production
# transform (Notifications.template_key + template_args + WhatsappReply.currency) — and
# passes the message-format contract. A template added without a case here fails the
# completeness check (Phase 4's summaries must register theirs, type: :digest).
class Notifications::TemplateShapeTest < ActiveSupport::TestCase
  include NotificationShapeAssertions

  LOCALES = [ :"pt-BR", :en ].freeze

  # Resolved template key => the notification rows that render it, exactly as the Phase
  # 1–2 scanners snapshot them. Plural kinds run all their count branches (zero/one/other).
  CASES = {
    "bill_due"         => (0..3).map { |d| { kind: "bill_due", payload: { "name" => "Luz", "amount_cents" => 18_240, "due_on" => "2026-07-08", "days_until" => d } } },
    "bill_overdue"     => [ 1, 3 ].map { |d| { kind: "bill_overdue", payload: { "name" => "Luz", "amount_cents" => 18_240, "due_on" => "2026-07-04", "days_overdue" => d } } },
    "card_closing"     => (0..3).map { |d| { kind: "card_bill", payload: { "event" => "closing", "card" => "Nubank", "amount_cents" => 234_056, "date" => "2026-07-10", "days_until" => d } } },
    "card_due"         => (0..3).map { |d| { kind: "card_bill", payload: { "event" => "due", "card" => "Nubank", "amount_cents" => 234_056, "date" => "2026-07-17", "days_until" => d } } },
    "income_expected"  => (0..3).map { |d| { kind: "income_expected", payload: { "name" => "Salário", "amount_cents" => 450_000, "expected_on" => "2026-07-05", "days_until" => d } } },
    "budget_warn"      => [ { kind: "budget_warn", payload: { "category" => "Restaurantes", "spent_cents" => 50_000, "budget_cents" => 60_000, "left_cents" => 10_000 } } ],
    "budget_breach"    => [ { kind: "budget_breach", payload: { "category" => "Restaurantes", "spent_cents" => 66_000, "budget_cents" => 60_000, "left_cents" => 0 } } ],
    "surplus_nudge"    => [ { kind: "surplus_nudge", payload: { "surplus_cents" => 40_000, "savings_account_id" => 1 }, type: :suggestion } ],
    "rightsize_budget" => [ { kind: "rightsize_budget", payload: { "category" => "Lazer", "budget_cents" => 60_000, "typical_cents" => 30_000 }, type: :suggestion } ]
  }.freeze

  LOCALES.each do |locale|
    test "every notification template in #{locale} has a case here (completeness)" do
      templates = I18n.t("whatsapp.replies.notifications", locale: locale, fallback: false)
      assert_equal CASES.keys.sort, templates.keys.map(&:to_s).sort,
                   "whatsapp.replies.notifications.* and the shape cases must cover each other"
    end

    test "every notification template passes the 08 shape contract in #{locale}" do
      CASES.each do |template_key, variants|
        variants.each do |variant|
          body = render(template_key, locale: locale, **variant)
          assert_notification_shape(body, type: variant.fetch(:type, :alert),
                                          label: "#{template_key} (#{locale}): #{body}")
        end
      end
    end
  end

  private

  # The production render path, minus the wire: shared key resolution + shared payload
  # transform + the job-context money formatter, inside the recipient's locale.
  def render(template_key, kind:, payload:, locale:, type: :alert)
    notification = Notification.new(kind: kind, payload: payload)
    assert_equal template_key, Notifications.template_key(notification),
                 "the shared key resolution must map this payload to #{template_key}"
    args = Notifications.template_args(notification) { |cents| WhatsappReply.currency(cents, locale: locale) }
    I18n.with_locale(locale) { I18n.t("whatsapp.replies.notifications.#{template_key}", raise: true, **args) }
  end
end
