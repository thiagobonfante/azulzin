require "test_helpers/e2e/pipeline_case"

# WA-CAP multi-expense batch: one message carrying several expenses (.plans/e2e/03 §2).
# Posture per item is identical to single capture; the reply is ONE message for the batch.
class E2E::WhatsappMultiCaptureTest < E2E::PipelineCase
  # WA-CAP-37 — one instrument named anywhere applies to every item
  test "three expenses, one card named → all post on that card, one summary reply" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupas" },
      { cents: 1_122,  merchant: "pedágio" },
      { cents: 5_590,  merchant: "almoço", method: "credito", instrument: "nubank" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "197 roupas, 11,22 pedágio, 55,90 almoço credito nubank")
      drain_jobs!
    end

    txns = batch_rows(s, msg)
    assert_equal 3, txns.size
    assert_equal [ 19_700, 1_122, 5_590 ], txns.map(&:amount_cents)
    txns.each do |t|
      assert t.posted?
      assert_equal s.nubank_card, t.credit_card
      assert_equal s.nubank_card.billing_month_for(t.occurred_on), t.billing_month
    end
    assert_wa_reply(s.jid, equals: summary_golden(
      line(:posted, 19_700, "roupas",  s.nubank_card),
      line(:posted, 1_122,  "pedágio", s.nubank_card),
      line(:posted, 5_590,  "almoço",  s.nubank_card)))
  end

  # WA-CAP-38 — per-item instruments win when several are named
  test "per-line instruments → each expense lands on its own instrument" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupa",  method: "debito",  instrument: "itau" },
      { cents: 1_122,  merchant: "pedágio", method: "debito", instrument: "itau" },
      { cents: 5_590,  merchant: "almoço", method: "credito", instrument: "nubank" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "197 roupa debito itau\n11,22 pedágio debito itau\n55,90 almoço credito nubank")
      drain_jobs!
    end

    roupa, pedagio, almoco = batch_rows(s, msg)
    assert_equal s.itau, roupa.bank_account
    assert_equal s.itau, pedagio.bank_account
    assert_equal s.nubank_card, almoco.credit_card
    assert batch_rows(s, msg).all?(&:posted?)
    assert_equal 1, fake_sidecar.messages_to(s.jid).size, "one confirmation for the whole batch"
    assert_wa_reply(s.jid, equals: summary_golden(
      line(:posted, 19_700, "roupa",   s.itau),
      line(:posted, 1_122,  "pedágio", s.itau),
      line(:posted, 5_590,  "almoço",  s.nubank_card)))
  end

  # WA-CAP-39 — exactly one unresolved item → the rest post, ONE targeted numbered ask;
  # the answer posts it and the confirmation is the whole batch's summary, in message order.
  test "one bare item among named ones → targeted ask, answer completes the batch summary" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupa",  method: "debito",  instrument: "itau" },
      { cents: 1_122,  merchant: "pedágio" },
      { cents: 5_590,  merchant: "almoço", method: "credito", instrument: "nubank" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "197 roupa debito itau\n11,22 pedágio\n55,90 almoço credito nubank")
      drain_jobs!
    end

    roupa, pedagio, almoco = batch_rows(s, msg)
    assert roupa.posted?
    assert almoco.posted?
    assert_equal "needs_clarification", pedagio.status
    options = "1. #{s.itau.display_name}\n2. #{s.nubank_card.display_name}"
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.multi_ask_instrument",
                                          amount: brl(1_122), label: "pedágio",
                                          options: options, locale: :"pt-BR"))

    wa_inject(s.jid, "2")
    drain_jobs!

    pedagio.reload
    assert pedagio.posted?
    assert_equal s.nubank_card, pedagio.credit_card
    assert_equal s.nubank_card.billing_month_for(pedagio.occurred_on), pedagio.billing_month
    assert_wa_reply(s.jid, equals: summary_golden(
      line(:posted, 19_700, "roupa",   s.itau),
      line(:posted, 1_122,  "pedágio", s.nubank_card),
      line(:posted, 5_590,  "almoço",  s.nubank_card)))
  end

  # WA-CAP-40 — two or more unresolved items → post NOTHING, ask for a resend
  test "two unresolved items → nothing posts, user is asked to specify per transaction" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    s.account.bank_accounts.create!(institution: Institution.find_by!(code: "033"),
                                    nickname: "Santander E2E", created_by: s.owner)

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupa", method: "debito" },   # débito with TWO checking accounts
      { cents: 1_122,  merchant: "pedágio" },
      { cents: 5_590,  merchant: "almoço", method: "credito", instrument: "nubank" }
    ])
    with_canned_ai(extraction: extraction) do
      wa_inject(s.jid, "197 roupa debito\n11,22 pedágio\n55,90 almoço credito nubank")
      drain_jobs!
    end

    assert_equal 0, s.account.transactions.count
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.multi_specify", locale: :"pt-BR"))
  end

  # WA-CAP-41 — a below-floor item parks (review tray is its confirmation), siblings post
  test "low-confidence item parks while the rest post, both named in the summary" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 8_490, merchant: "mercado", method: "debito", instrument: "itau" },
      { cents: 2_000, merchant: "feira", confidence: 0.5 }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "mercado 84,90 no itau e feira uns 20")
      drain_jobs!
    end

    mercado, feira = batch_rows(s, msg)
    assert mercado.posted?
    assert_equal s.itau, mercado.bank_account
    assert_equal "pending_review", feira.status
    assert_wa_reply(s.jid, equals: summary_golden(
      line(:posted, 8_490, "mercado", s.itau),
      line(:parked, 2_000, "feira")))
  end

  # WA-CAP-42 — no instrument named anywhere: same posture as a bare single message
  test "no instruments in the whole message → all post unassigned, one summary" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 19_700, merchant: "roupas" },
      { cents: 1_122,  merchant: "pedágio" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "197 roupas, 11,22 pedágio")
      drain_jobs!
    end

    txns = batch_rows(s, msg)
    assert_equal 2, txns.size
    txns.each { |t| assert t.posted? && t.instrument.nil? }
    assert_wa_reply(s.jid, equals: summary_golden(
      line(:unassigned, 19_700, "roupas"),
      line(:unassigned, 1_122,  "pedágio")))
  end

  # WA-CAP-43 — degenerate split (one usable item) falls back to the single-expense path
  test "items with a single usable amount → plain single capture, no batch rows" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    extraction = E2E::CannedAI.multi_expense(items: [
      { cents: 3_000, merchant: "padaria", method: "debito", instrument: "itau" },
      { cents: nil,   merchant: "uma coisinha" }
    ])
    msg = nil
    with_canned_ai(extraction: extraction) do
      msg = wa_inject(s.jid, "padaria 30 no itau e uma coisinha")
      drain_jobs!
    end

    txn = s.account.transactions.sole
    assert txn.posted?
    assert_equal msg.wa_message_id, txn.source_message_id, "single path keeps the unsuffixed id"
    assert_equal s.itau, txn.bank_account
  end

  private

  # Batch rows in message order (source_message_id "<wa_id>#<index>").
  def batch_rows(s, msg)
    Whatsapp::MultiExpenseHandler.batch_rows(s.account, msg.wa_message_id)
  end

  def summary_golden(*lines)
    I18n.t("whatsapp.replies.multi_posted", count: lines.size, lines: lines.join("\n"),
           locale: :"pt-BR")
  end

  def line(kind, cents, label, instrument = nil)
    case kind
    when :posted
      I18n.t("whatsapp.replies.multi_line_posted", amount: brl(cents), label: label,
             instrument: instrument.display_name, locale: :"pt-BR")
    when :unassigned
      I18n.t("whatsapp.replies.multi_line_unassigned", amount: brl(cents), label: label,
             locale: :"pt-BR")
    when :parked
      I18n.t("whatsapp.replies.multi_line_parked", amount: brl(cents), label: label,
             locale: :"pt-BR")
    end
  end
end
