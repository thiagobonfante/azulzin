require "test_helpers/e2e/pipeline_case"

# SUB-01 — sub-cards + default card (.plans/credit-cards 04/05 phase 6): the count-once
# invariant on the calibrated family pack, root-cycle bucketing at the write sites, the
# WA-CAP additions (nickname silent post, default-card silent post, explicit wins,
# root-over-child tie), the delete-root guard and the simple-case regression.
class E2E::WebSubCardsTest < E2E::PipelineCase
  # SUB-01 — Σ over roots' bill_cents covers root+child rows exactly once, frozen cents.
  test "count-once invariant: the family bill is 60.000¢, counted once, closed once" do
    s = E2E::Scenario.build(:card_family)
    month = Date.current.beginning_of_month

    assert_equal 60_000, s.nubank_card.bill_cents(month)
    assert_equal 60_000, MonthSummary.new(s.account, month).faturas_cents, "roots iteration — no double count"

    CardBills::CloseScanJob.perform_now
    bill = s.account.card_bills.sole
    assert_equal s.nubank_card.id, bill.credit_card_id, "sub-cards never own bills"
    assert_equal 60_000, bill.computed_total_cents
  end

  test "sub-card rows bucket by the ROOT's cycle at every write site" do
    s = E2E::Scenario.build(:card_family)
    open_month = s.nubank_card.current_open_bill_month

    # Manual-entry path: a purchase past the root's closing lands on the OPEN bill.
    row = s.expense(merchant: "Depois do Corte", category: "Outros", instrument: s.filha_card,
                    cents: 5_000, on: Date.current)
    assert_equal open_month, row.billing_month

    # Installments path: parcel 1 rides the root's cycle too.
    plan = Installments::Create.call(account: s.account, created_by: s.owner, card: s.ifood_virtual,
                                     total_cents: 30_000, count: 3, occurred_on: Date.current, merchant: "Fone")
    assert_equal open_month, plan.starts_on
  end

  # WA-CAP — "50 no crédito da filha" posts to the sub-card, silently, naming it.
  test "WA: nickname phrase posts silently to the sub-card" do
    s = E2E::Scenario.build(:card_family).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "lanche",
                                                     method: "credito", instrument: "crédito da filha")) do
      wa_inject(s.jid, "50 no crédito da filha")
      drain_jobs!
    end

    txn = s.account.transactions.where(source: "whatsapp_text").sole
    assert txn.posted?
    assert_equal s.filha_card.id, txn.credit_card_id
    assert_equal s.nubank_card.current_open_bill_month, txn.billing_month, "root's cycle"
    assert_wa_reply s.jid, includes: [ "cartão da filha" ]
  end

  # WA-CAP — P0 #3: no phrase + default set → silent post to the default, reply names it.
  test "WA: no instrument phrase posts silently to the sender's default card, named in the reply" do
    s = E2E::Scenario.build(:card_family).wa_verified!
    s.owner.update!(default_credit_card_id: s.nubank_card.id)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "posto", method: "credito")) do
      wa_inject(s.jid, "50 no crédito")
      drain_jobs!
    end

    txn = s.account.transactions.where(source: "whatsapp_text").sole
    assert txn.posted?
    assert_equal s.nubank_card.id, txn.credit_card_id
    assert_wa_reply s.jid, includes: [ s.nubank_card.display_name ]
  end

  test "WA: with no default, several cards still get the numbered ask (unchanged)" do
    s = E2E::Scenario.build(:card_family).wa_verified!
    assert_nil s.owner.default_credit_card

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "posto", method: "credito")) do
      wa_inject(s.jid, "50 no crédito")
      drain_jobs!
    end

    assert_equal "needs_clarification", s.account.transactions.where(source: "whatsapp_text").sole.status
  end

  # WA-CAP — an explicit phrase always beats the default.
  test "WA: explicit phrase wins over the default card" do
    s = E2E::Scenario.build(:card_family).wa_verified!
    s.owner.update!(default_credit_card_id: s.filha_card.id)

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "ifood",
                                                     method: "credito", instrument: "virtual ifood")) do
      wa_inject(s.jid, "50 no virtual ifood")
      drain_jobs!
    end

    assert_equal s.ifood_virtual.id, s.account.transactions.where(source: "whatsapp_text").sole.credit_card_id
  end

  # WA-CAP — a root/child tie ("nubank" matches the whole family) prefers the ROOT.
  test "WA: root-over-child tie posts silently to the root" do
    s = E2E::Scenario.build(:card_family).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_000, merchant: "posto",
                                                     method: "credito", instrument: "nubank")) do
      wa_inject(s.jid, "50 no nubank")
      drain_jobs!
    end

    txn = s.account.transactions.where(source: "whatsapp_text").sole
    assert txn.posted?
    assert_equal s.nubank_card.id, txn.credit_card_id, "the root is the default plastic"
  end

  test "deleting a root with kept sub-cards is refused with the friendly error" do
    s = E2E::Scenario.build(:card_family)
    sign_in_as s.owner

    delete credit_card_url(s.nubank_card)

    assert_nil s.nubank_card.reload.deleted_at
    follow_redirect!
    assert_includes response.body, I18n.t(
      "activerecord.errors.models.credit_card.attributes.base.has_kept_children", locale: :"pt-BR")
  end

  test "first card ever auto-becomes its creator's default" do
    s = E2E::Scenario.build(:bare)
    sign_in_as s.owner

    post credit_cards_url, params: { credit_card: {
      institution_id: Institution.find_by!(code: "260").id, bill_due_day: 10, closing_offset_days: 7 } }

    card = s.account.credit_cards.kept.sole
    assert_equal card.id, s.owner.reload.default_credit_card_id
  end

  # SUB-01 — simple case regression: one plain card sees zero sub-card/star UI.
  test "an account with one plain card renders no chip, no sub list, no star" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner

    get credit_cards_url
    assert_response :success
    assert_not_includes response.body, I18n.t("credit_cards.sub_cards.chip.one", locale: :"pt-BR")
    assert_not_includes response.body, I18n.t("credit_cards.default.set", locale: :"pt-BR")
  end

  # 04 §5: the star renders the SIGNED-IN member's default — each spouse their own plastic.
  test "the default star follows the signed-in member" do
    s = E2E::Scenario.build(:couple)
    s.owner.update!(default_credit_card_id: s.nubank_card.id)
    s.partner.update!(default_credit_card_id: s.partner_card.id)

    sign_in_as s.owner
    get credit_cards_url
    assert_select "form[action='#{make_default_credit_card_path(s.nubank_card)}'] svg[fill='currentColor']"
    assert_select "form[action='#{make_default_credit_card_path(s.partner_card)}'] svg[fill='none']"

    sign_in_as s.partner
    get credit_cards_url
    assert_select "form[action='#{make_default_credit_card_path(s.partner_card)}'] svg[fill='currentColor']"
    assert_select "form[action='#{make_default_credit_card_path(s.nubank_card)}'] svg[fill='none']"
  end

  # In-app form precedence: explicit pick > member default > lone card.
  test "manual entry with método crédito and no pick lands on the member's default card" do
    s = E2E::Scenario.build(:card_family)
    s.owner.update!(default_credit_card_id: s.ifood_virtual.id)
    sign_in_as s.owner

    post transactions_url, params: { transaction: {
      amount_reais: "35,00", merchant: "Padoca", payment_method: "credito",
      occurred_on: Date.current.iso8601, direction: "expense" } }

    txn = s.account.transactions.order(:id).last
    assert_equal s.ifood_virtual.id, txn.credit_card_id
  end
end
