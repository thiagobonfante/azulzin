require "test_helpers/e2e/pipeline_case"

# MU-09 + NT-X-02: the family promise through the real pipeline — two phones, one ledger,
# per-member attribution, per-member notification ownership (.plans/e2e/05 §6).
class E2E::WhatsappMultiUserTest < E2E::PipelineCase
  test "both members capture from their own phones into ONE ledger with correct attribution" do
    s = E2E::Scenario.build(:couple)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "mercado",
                                                     method: "debito", instrument: "itau")) do
      wa_inject(s.jid(s.owner), "mercado 54,90")
      drain_jobs!
    end
    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 12_030, merchant: "farmácia",
                                                     method: "debito", instrument: "itau")) do
      wa_inject(s.jid(s.partner), "farmácia 120,30")
      drain_jobs!
    end

    rows = s.account.transactions.where.not(whatsapp_message_id: nil).order(:amount_cents)
    assert_equal [ 5_490, 12_030 ], rows.pluck(:amount_cents)
    assert_equal [ s.owner.id, s.partner.id ], rows.pluck(:created_by_id),
                 "each row is attributed to the phone that sent it"

    # Both phones see the SAME month — the shared-money promise, asked over WhatsApp.
    summary = MonthSummary.new(s.account, Date.current.beginning_of_month)
    assert_equal 17_520, summary.expenses_cents

    s.members.each do |member|
      fake_sidecar.reset!
      with_canned_ai(extraction: E2E::CannedAI.query(nil)) do
        wa_inject(s.jid(member), "como tá o mês?")
        drain_jobs!
      end
      assert_brl 17_520, assert_wa_reply(s.jid(member)),
                 "#{member.display_name} must see the household total"
    end
  end

  test "a member cannot dismiss another member's notification" do
    s = E2E::Scenario.build(:couple)
    owners_row = Notification.record!(user: s.owner, account: s.account, kind: "bill_due",
                                      period_key: Date.current,
                                      payload: { name: "Luz", amount_cents: 18_500, days_until: 1 })

    sign_in_as s.partner
    post dismiss_notification_path(owners_row)

    assert_response :not_found
    assert_nil owners_row.reload.dismissed_at
  end
end
