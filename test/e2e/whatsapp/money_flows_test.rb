require "test_helpers/e2e/pipeline_case"

# WA-CAP money flows: income, transfers, installments, commitment payment, edit, undo
# (.plans/e2e/03 §2).
class E2E::WhatsappMoneyFlowsTest < E2E::PipelineCase
  # WA-CAP-07
  test "income: recebi o salário posts an income row with exact cents" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.income(cents: 500_000, merchant: "salário")) do
      wa_inject(s.jid, "recebi o salário 5000")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal "income", txn.direction
    assert txn.posted?
    assert_equal 500_000, txn.amount_cents
    assert_brl 500_000, assert_wa_reply(s.jid)
  end

  # WA-CAP-08
  test "transfer to the caixinha: one posted row, both legs, savings reply" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!.add_caixinha!

    with_canned_ai(extraction: E2E::CannedAI.transfer(cents: 30_000, from: "itau", to: "caixinha")) do
      wa_inject(s.jid, "guardei 300 na caixinha")
      drain_jobs!
    end

    txn = s.account.transactions.where(direction: "transfer").sole
    assert txn.posted?
    assert_equal 30_000, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal s.caixinha, txn.transfer_to_bank_account
    assert_nil txn.category_id, "transfers are never categorized"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.transfer_saved",
                                          amount: brl(30_000),
                                          instrument: s.caixinha.display_name, locale: :"pt-BR"))
  end

  # WA-CAP-09 (one chained leg: destination unmatched → numbered ask → pick resolves)
  test "transfer with unmatched destination asks with numbered options, the pick posts it" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!.add_caixinha!

    with_canned_ai(extraction: E2E::CannedAI.transfer(cents: 20_000, from: "itau", to: "misteriosa")) do
      wa_inject(s.jid, "transferi 200")
      drain_jobs!
    end
    ask = s.account.transactions.where(direction: "transfer").sole
    assert_equal "transfer_to", ask.ask["slot"]
    assert_includes assert_wa_reply(s.jid), "1. #{s.caixinha.display_name}",
                    "savings come first in the prompt order"

    wa_inject(s.jid, "1")
    drain_jobs!

    ask.reload
    assert ask.posted?
    assert_equal s.caixinha, ask.transfer_to_bank_account
    assert_equal s.itau, ask.bank_account
  end

  # WA-CAP-10
  test "card installments: even split posts one commitment riding the fatura" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 349_900, count: 10,
                                                         merchant: "Notebook", instrument: "nubank")) do
      wa_inject(s.jid, "notebook 3499 em 10x no nubank")
      drain_jobs!
    end

    c = s.account.commitments.sole
    assert_equal "installment", c.kind
    assert_equal s.nubank_card, c.credit_card
    assert_equal 349_900, c.total_cents
    assert_equal 10, c.installments_count
    assert_equal 34_990, c.amount_cents
    assert_brl 34_990, assert_wa_reply(s.jid)
  end

  # WA-CAP-11
  test "card installments: uneven split never loses a centavo" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 70_005, count: 7,
                                                         merchant: "Sofá", instrument: "nubank")) do
      wa_inject(s.jid, "sofá 700,05 em 7x no nubank")
      drain_jobs!
    end

    c = s.account.commitments.sole
    assert_equal 70_005, c.total_cents
    assert_equal 10_001, c.amount_cents, "the first parcels carry the extra centavo"
    assert_equal 70_005, Installments::Create.split_cents(c.total_cents, c.installments_count).sum
    assert_brl 10_001, assert_wa_reply(s.jid)
  end

  # WA-CAP-13
  test "debit installments become a bank-sourced commitment" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 168_000, count: 6,
                                                         merchant: "Sofá", method: "debito",
                                                         instrument: "itau")) do
      wa_inject(s.jid, "sofá 1680 em 6x no débito do itaú")
      drain_jobs!
    end

    c = s.account.commitments.sole
    assert_equal "installment", c.kind
    assert_equal s.itau, c.bank_account
    assert_nil c.credit_card
    assert_equal 28_000, c.amount_cents
  end

  # WA-CAP-12
  test "low-confidence installment parks one stub instead of fanning out" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 500_000, count: 10,
                                                         merchant: "tv", instrument: "nubank",
                                                         confidence: 0.5)) do
      wa_inject(s.jid, "acho que 5000 em 10x")
      drain_jobs!
    end

    assert_empty s.account.commitments, "below the floor no commitment is minted"
    assert s.account.transactions.sole.pending_review?
  end

  # WA-CAP-14
  test "paguei o condomínio marks this month's occurrence paid" do
    s = E2E::Scenario.build(:reminders_due).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "condomínio")) do
      wa_inject(s.jid, "paguei o condomínio")
      drain_jobs!
    end

    payment = s.account.transactions.where(commitment: s.bill("Condomínio")).order(:created_at).last
    assert payment.posted?
    assert_equal 48_000, payment.amount_cents
    assert_equal Date.current.beginning_of_month, payment.billing_month
    assert_includes assert_wa_reply(s.jid), "Condomínio"
  end

  # WA-CAP-15
  test "ambiguous commitment asks a numbered pick, the reply pays the right one" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    start = Date.current.beginning_of_month
    seguro = s.account.commitments.create!(
      kind: "fixed", name: "Seguro do Carro", bank_account: s.itau, category: s.category("Transporte"),
      amount_cents: 21_000, starts_on: start, schedule_day: 25, created_by: s.owner)
    s.account.commitments.create!(
      kind: "fixed", name: "Parcela do Carro", bank_account: s.itau, category: s.category("Transporte"),
      amount_cents: 45_000, starts_on: start, schedule_day: 26, created_by: s.owner)

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "carro")) do
      wa_inject(s.jid, "paguei o carro")
      drain_jobs!
    end
    options_reply = assert_wa_reply(s.jid)
    assert_match(/1\. .*\n2\. /, options_reply, "must offer a numbered pick")
    first_option = options_reply[/1\. (.+)/, 1]

    wa_inject(s.jid, "1")
    drain_jobs!

    paid = s.account.transactions.where.not(commitment_id: nil).sole
    assert_equal first_option, paid.commitment.name, "the numbered reply must pay the listed option"
    assert_equal seguro, paid.commitment if first_option == seguro.name
  end

  # WA-CAP-16
  test "edit amount: na verdade foi 54,90 corrects the SAME row" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    post_wa_expense(s, cents: 5_900, merchant: "padaria")

    with_canned_ai(extraction: E2E::CannedAI.edit_last(field_hint: "amount", cents: 5_490)) do
      wa_inject(s.jid, "na verdade foi 54,90")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal 5_490, txn.amount_cents
    assert_brl 5_490, assert_wa_reply(s.jid)
  end

  # WA-CAP-17
  test "edit category: muda pra mercado flips provenance to user (feeds memory)" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    post_wa_expense(s, cents: 5_490, merchant: "padaria")

    with_canned_ai(extraction: E2E::CannedAI.edit_last(field_hint: "category", category: "Mercado")) do
      wa_inject(s.jid, "muda pra mercado")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal s.category("Mercado").id, txn.category_id
    assert_equal "user", txn.category_source, "a spoken correction is human signal"
  end

  # WA-CAP-18
  test "edit beyond 24h is refused and the row untouched" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    post_wa_expense(s, cents: 5_900, merchant: "padaria")

    travel 25.hours
    with_canned_ai(extraction: E2E::CannedAI.edit_last(field_hint: "amount", cents: 1_000)) do
      wa_inject(s.jid, "na verdade foi 10")
      drain_jobs!
    end

    assert_equal 5_900, s.account.transactions.sole.amount_cents
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.nothing_to_edit", locale: :"pt-BR"))
  end

  # WA-CAP-19 — zero-LLM regex pre-pass, no canned AI needed
  test "apaga o último reverses the last WA row and restores the balance" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    s.itau.update!(balance_cents: 100_000)
    travel 1.minute   # frozen clock: the anchor and the row must not share the same instant
    post_wa_expense(s, cents: 5_490, merchant: "padaria", instrument: "itau", method: "debito")
    assert_equal 94_510, s.itau.reload.derived_balance_cents

    wa_inject(s.jid, "apaga o último")
    drain_jobs!

    assert s.account.transactions.sole.rejected?
    assert_equal 100_000, s.itau.reload.derived_balance_cents, "the balance must be restored exactly"
    assert_brl 5_490, assert_wa_reply(s.jid)
  end

  # WA-CAP-20
  test "undo with nothing to undo replies gracefully and mutates nothing" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    wa_inject(s.jid, "apaga o último")
    drain_jobs!

    assert_empty s.account.transactions
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.nothing_to_undo", locale: :"pt-BR"))
  end

  # WA-CAP-29 (coverage audit): move_bill wired — was classified but never executed
  test "joga pra próxima fatura moves the captured purchase one fatura over" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    post_wa_expense(s, cents: 8_490, merchant: "mercado", instrument: "nubank", method: "credito")

    txn = s.account.transactions.sole
    assert_equal s.nubank_card, txn.credit_card
    original = txn.billing_month

    with_canned_ai(extraction: E2E::CannedAI.move_bill(target: "próxima fatura")) do
      wa_inject(s.jid, "joga pra próxima fatura")
      drain_jobs!
    end

    txn.reload
    assert_equal original >> 1, txn.billing_month
    assert txn.billing_month_manual?
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.bill_moved",
                                          merchant: "mercado", amount: brl(8_490),
                                          month: I18n.l(original >> 1, format: :month_year, locale: :"pt-BR"),
                                          locale: :"pt-BR"))
  end

  private

  def post_wa_expense(s, cents:, merchant:, instrument: nil, method: "desconhecido")
    with_canned_ai(extraction: E2E::CannedAI.expense(cents: cents, merchant: merchant,
                                                     method: method, instrument: instrument)) do
      wa_inject(s.jid, "#{merchant} #{format('%d,%02d', cents / 100, cents % 100)}")
      drain_jobs!
    end
    fake_sidecar.reset!   # keep reply assertions scoped to what the test itself triggers
  end
end
