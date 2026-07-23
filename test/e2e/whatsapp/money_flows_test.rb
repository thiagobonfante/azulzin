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

  # WA-CAP-07b — income always lands in a bank account (2026-07-11): sole checking self-picks
  test "income with no account named and a sole checking account → posts assigned" do
    s = E2E::Scenario.build(:solo_basic).add_savings_account!.wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.income(cents: 120_000, merchant: "freela")) do
      wa_inject(s.jid, "caiu 1200 de um freela")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal s.itau, txn.bank_account, "sole checking account self-picks (savings account excluded)"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.income_posted", amount: brl(120_000),
                                          instrument: s.itau.display_name, locale: :"pt-BR"))
  end

  # WA-CAP-07c — several checking accounts → numbered pick with income wording
  test "income with two checking accounts → numbered account ask, answer posts" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    second = s.account.bank_accounts.create!(
      institution: Institution.find_by!(code: "260"), nickname: "Nubank Conta", created_by: s.owner)

    with_canned_ai(extraction: E2E::CannedAI.income(cents: 120_000, merchant: "freela")) do
      wa_inject(s.jid, "caiu 1200 de um freela")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert_equal "needs_clarification", txn.status
    options = "1. #{s.itau.display_name}\n2. #{second.display_name}"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.ask_income_account_pick",
                                          amount: brl(120_000), options: options, locale: :"pt-BR"))

    wa_inject(s.jid, "2")
    drain_jobs!

    txn.reload
    assert txn.posted?
    assert_equal "income", txn.direction
    assert_equal second, txn.bank_account
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.income_posted", amount: brl(120_000),
                                          instrument: second.display_name, locale: :"pt-BR"))
  end

  # WA-CAP-08
  test "transfer to the savings account: one posted row, both legs, savings reply" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!.add_savings_account!

    with_canned_ai(extraction: E2E::CannedAI.transfer(cents: 30_000, from: "itau", to: "caixinha")) do
      wa_inject(s.jid, "guardei 300 na caixinha")
      drain_jobs!
    end

    txn = s.account.transactions.where(direction: "transfer").sole
    assert txn.posted?
    assert_equal 30_000, txn.amount_cents
    assert_equal s.itau, txn.bank_account
    assert_equal s.savings_account, txn.transfer_to_bank_account
    assert_nil txn.category_id, "transfers are never categorized"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.transfer_saved",
                                          amount: brl(30_000),
                                          instrument: s.savings_account.display_name, locale: :"pt-BR"))
  end

  # WA-CAP-09 (one chained leg: destination unmatched → numbered ask → pick resolves)
  test "transfer with unmatched destination asks with numbered options, the pick posts it" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!.add_savings_account!

    with_canned_ai(extraction: E2E::CannedAI.transfer(cents: 20_000, from: "itau", to: "misteriosa")) do
      wa_inject(s.jid, "transferi 200")
      drain_jobs!
    end
    ask = s.account.transactions.where(direction: "transfer").sole
    assert_equal "transfer_to", ask.ask["slot"]
    assert_includes assert_wa_reply(s.jid), "1. #{s.savings_account.display_name}",
                    "savings come first in the prompt order"

    wa_inject(s.jid, "1")
    drain_jobs!

    ask.reload
    assert ask.posted?
    assert_equal s.savings_account, ask.transfer_to_bank_account
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

  # WA-CAP-10 / CAT-EXP-07 regression: parcel-first phrasing ("10x de 349,90") extracts with
  # amount_raw null — it must still fan out, not park (found live 2026-07-11, ch. 8 walk).
  test "card installments: parcel-first phrasing posts instead of parking" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment_parcel_first(
      parcel_cents: 34_990, count: 10, merchant: "Magalu", instrument: "nubank",
      transcript: "magalu 10x de 349,90 no nubank", confidence: 1.0)) do
      wa_inject(s.jid, "magalu 10x de 349,90 no nubank")
      drain_jobs!
    end

    c = s.account.commitments.sole
    assert_equal "installment", c.kind
    assert_equal s.nubank_card, c.credit_card
    assert_equal 349_900, c.total_cents
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

  # WA-CAP-10b — "1000 parcelado" (2026-07-11): no card named + no count → card pick chains
  # into the count ask; the answers create the plan on the picked card.
  test "parcelado with no card and no count → card ask, then count ask, then the plan" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    second = s.account.credit_cards.create!(
      institution: Institution.find_by!(code: "341"), nickname: "Cartão Itaú",
      bill_due_day: 15, closing_offset_days: 7, credit_limit_cents: 100_000, created_by: s.owner)

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 100_000, count: nil,
                                                         merchant: nil, instrument: nil)) do
      wa_inject(s.jid, "1000 parcelado")
      drain_jobs!
    end
    options = "1. #{s.nubank_card.display_name}\n2. #{second.display_name}"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.ask_card_pick",
                                          amount: brl(100_000), options: options, locale: :"pt-BR"))

    wa_inject(s.jid, "2")
    drain_jobs!
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.ask_installments_count", locale: :"pt-BR"))

    wa_inject(s.jid, "10")
    drain_jobs!

    c = s.account.commitments.sole
    assert_equal second, c.credit_card
    assert_equal 100_000, c.total_cents
    assert_equal 10, c.installments_count
    assert_equal 10_000, c.amount_cents
  end

  # WA-CAP-10c — a sole card self-picks for an instrument-less parcelado
  test "parcelado with no card named and a single card → plan on that card, no ask" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 50_000, count: 5,
                                                         merchant: nil, instrument: nil)) do
      wa_inject(s.jid, "500 em 5x parcelado")
      drain_jobs!
    end

    c = s.account.commitments.sole
    assert_equal s.nubank_card, c.credit_card
    assert_equal 5, c.installments_count
  end

  # WA-CAP-10d — count outside 1–24 parks for review instead of fanning out
  test "parcelado em 30x → parked stub, no commitment" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.installment(total_cents: 100_000, count: 30,
                                                         merchant: "Geladeira", instrument: "nubank")) do
      wa_inject(s.jid, "geladeira 1000 em 30x no nubank")
      drain_jobs!
    end

    assert_equal 0, s.account.commitments.count
    txn = s.account.transactions.sole
    assert_equal "pending_review", txn.status
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.parked", locale: :"pt-BR"))
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

  # WA-CAP-15b — a bare "paguei a parcela" (2026-07-11): no identity words → numbered pick
  # over the installments, never commitment_not_found while candidates exist.
  test "generic paguei a parcela offers the installment pick instead of not-found" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    start = Date.current.beginning_of_month << 1
    %w[Sofá Notebook].each_with_index do |name, i|
      s.account.commitments.create!(
        kind: "installment", name: name, bank_account: s.itau,
        amount_cents: 28_000 + i, total_cents: (28_000 + i) * 6, installments_count: 6,
        schedule_kind: "fixed_day", schedule_day: 15 + i, starts_on: start, created_by: s.owner)
    end

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "a parcela",
                                                            transcript: "paguei a parcela")) do
      wa_inject(s.jid, "paguei a parcela")
      drain_jobs!
    end
    options_reply = assert_wa_reply(s.jid)
    assert_match(/1\. .*\n2\. /, options_reply, "must offer a numbered pick")
    second_option = options_reply[/2\. (.+)/, 1]

    wa_inject(s.jid, "2")
    drain_jobs!

    paid = s.account.transactions.where.not(commitment_id: nil).sole
    assert_equal second_option, paid.commitment.name
    assert_equal Date.current.beginning_of_month, paid.billing_month
  end

  # WA-CAP-15c — explicit future month → value confirmation; *sim* pays the expected parcel
  test "future-month parcel asks value confirmation, sim pays the expected amount" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sofa = s.account.commitments.create!(
      kind: "installment", name: "Sofá", bank_account: s.itau,
      amount_cents: 28_000, total_cents: 168_000, installments_count: 6,
      schedule_kind: "fixed_day", schedule_day: 15,
      starts_on: Date.current.beginning_of_month << 1, created_by: s.owner)
    next_month = Date.current.beginning_of_month >> 1

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "sofá", target_bill_raw: "mês que vem")) do
      wa_inject(s.jid, "paguei a parcela do sofá do mês que vem")
      drain_jobs!
    end
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.ask_pay_confirm", name: "Sofá",
      month: I18n.l(next_month, format: :month_year), amount: brl(28_000), locale: :"pt-BR"))

    wa_inject(s.jid, "sim")
    drain_jobs!

    paid = s.account.transactions.where(commitment: sofa).sole
    assert_equal 28_000, paid.amount_cents
    assert_equal next_month, paid.billing_month
  end

  # WA-CAP-15d — a plausible custom value (±20% for a next-month parcel) posts as given
  test "future-month confirmation accepts a custom value within the threshold" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sofa = s.account.commitments.create!(
      kind: "installment", name: "Sofá", bank_account: s.itau,
      amount_cents: 28_000, total_cents: 168_000, installments_count: 6,
      schedule_kind: "fixed_day", schedule_day: 15,
      starts_on: Date.current.beginning_of_month << 1, created_by: s.owner)

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "sofá", target_bill_raw: "mês que vem")) do
      wa_inject(s.jid, "paguei a parcela do sofá do mês que vem")
      drain_jobs!
    end
    wa_inject(s.jid, "250")   # 10,7% off the R$ 280,00 parcel → plausible discount
    drain_jobs!

    paid = s.account.transactions.where(commitment: sofa).sole
    assert_equal 25_000, paid.amount_cents
  end

  # WA-CAP-15e — "última parcela": targets the plan's final month (±50% threshold);
  # an implausible value doubts once, *confirmo* then pays the doubted value.
  test "última parcela targets the final month; implausible value doubts, confirmo pays it" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sofa = s.account.commitments.create!(
      kind: "installment", name: "Sofá", bank_account: s.itau,
      amount_cents: 28_000, total_cents: 168_000, installments_count: 6,
      schedule_kind: "fixed_day", schedule_day: 15,
      starts_on: Date.current.beginning_of_month << 1, created_by: s.owner)
    last_month = sofa.last_month.beginning_of_month

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "última parcela do sofá",
                                                            transcript: "paguei a última parcela do sofá")) do
      wa_inject(s.jid, "paguei a última parcela do sofá")
      drain_jobs!
    end
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.ask_pay_confirm", name: "Sofá",
      month: I18n.l(last_month, format: :month_year), amount: brl(28_000), locale: :"pt-BR"))

    wa_inject(s.jid, "10")   # R$ 10,00 vs R$ 280,00 — far beyond even the 50% band
    drain_jobs!
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.pay_confirm_doubt", value: brl(1_000),
      month: I18n.l(last_month, format: :month_year), expected: brl(28_000), locale: :"pt-BR"))

    wa_inject(s.jid, "confirmo")
    drain_jobs!

    paid = s.account.transactions.where(commitment: sofa).sole
    assert_equal 1_000, paid.amount_cents
    assert_equal last_month, paid.billing_month
  end

  # WA-CAP-15f — paying the final open parcel celebrates the payoff (2026-07-11)
  test "paying the last parcel replies quitado, not 'faltam 0'" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sofa = s.account.commitments.create!(
      kind: "installment", name: "Sofá", bank_account: s.itau,
      amount_cents: 28_000, total_cents: 56_000, installments_count: 2,
      schedule_kind: "fixed_day", schedule_day: 15,
      starts_on: Date.current.beginning_of_month << 1, created_by: s.owner)
    Commitments::MarkPaid.call(sofa, sofa.starts_on, created_by: s.owner)   # parcel 1 already paid

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "sofá")) do
      wa_inject(s.jid, "paguei a parcela do sofá")
      drain_jobs!
    end

    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.commitment_completed", name: "Sofá",
      amount: brl(28_000), month: I18n.l(Date.current.beginning_of_month, format: :month_year),
      count: 2, locale: :"pt-BR"))
  end

  # WA-CAP-15g — the celebration also fires through the future-month confirmation path
  test "confirming the última parcela celebrates the payoff" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    sofa = s.account.commitments.create!(
      kind: "installment", name: "Sofá", bank_account: s.itau,
      amount_cents: 28_000, total_cents: 56_000, installments_count: 2,
      schedule_kind: "fixed_day", schedule_day: 15,
      starts_on: Date.current.beginning_of_month, created_by: s.owner)
    Commitments::MarkPaid.call(sofa, sofa.starts_on, created_by: s.owner)   # parcel 1 already paid
    last_month = sofa.last_month.beginning_of_month

    with_canned_ai(extraction: E2E::CannedAI.pay_commitment(phrase: "última parcela do sofá",
                                                            transcript: "paguei a última parcela do sofá")) do
      wa_inject(s.jid, "paguei a última parcela do sofá")
      drain_jobs!
    end
    wa_inject(s.jid, "230")   # within the ±20% next-month band
    drain_jobs!

    # ONE message: the celebration with the savings note as its footer line.
    assert_wa_reply(s.jid, equals: [
      I18n.t("whatsapp.replies.commitment_completed", name: "Sofá", amount: brl(23_000),
             month: I18n.l(last_month, format: :month_year), count: 2, locale: :"pt-BR"),
      I18n.t("whatsapp.replies.advance_saving_note", saved: brl(5_000), locale: :"pt-BR")
    ].join("\n"))
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
