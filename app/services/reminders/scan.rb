module Reminders
  # The F1 window scan (.plans/up-tier 02 §1–2): every reminder-worthy event for an account
  # whose date falls in [from, to] (inclusive, SP-time Dates), plus a short overdue grace
  # behind `from`. Pure — no rows written, no channel assumed; the caller records each event
  # per member via Notification.record! and hands the row to Notifications::Deliver.
  #
  # Three sources (02 §1):
  #   bill_due / bill_overdue — unpaid commitment occurrences (fixa / assinatura / parcela).
  #     Card-charged commitments are included: they remind via their occurrence's due_on,
  #     NEVER via the fatura — the fatura reminder below is the aggregate (anti-pattern 02 §6).
  #   card_closing / card_due — fatura closing + due for each billing-configured card.
  #     Two kinds (the dedup key is kind-scoped, so a closing landing on the previous
  #     month's due date never dedups away); distinct period_keys let both fire, once each.
  #   income_expected — expected incomes not yet received, checked through
  #     MonthSummary#income_received? (linked receipt OR unlinked deposit within ±10%),
  #     never a bare received check.
  #
  # period_key = the EVENT's date (due / closing / expected), so a lead-days window that
  # re-covers the same bill every morning dedupes into one Notification row by construction
  # (02 §4). payload snapshots everything the renderers need — name, integer cents, ISO
  # dates, days-until — so nothing re-queries and a later-deleted subject still renders.
  class Scan
    OVERDUE_GRACE_DAYS = 3   # unpaid bills get ONE "está vencida" nudge this many days back

    def self.call(account, from:, to:) = new(account, from: from, to: to).call

    def initialize(account, from:, to:)
      @account = account
      @from    = from
      @to      = to
    end

    def call = bill_events + card_events + card_overdue_events + income_events

    private

    # Unpaid occurrences due inside the window → bill_due; due within the grace behind it →
    # bill_overdue (its own kind + copy; the dedup key is still the due date, so however
    # many mornings re-scan it, the nudge is one row).
    def bill_events
      occurrences.filter_map do |occ|
        next if occ.paid?
        due = occ.due_on
        if due.between?(@from, @to)
          event("bill_due", occ.commitment, due,
                name: occ.commitment.name, amount_cents: occ.commitment.amount_cents,
                due_on: due.iso8601, days_until: (due - @from).to_i)
        elsif due.between?(@from - OVERDUE_GRACE_DAYS, @from - 1)
          event("bill_overdue", occ.commitment, due,
                name: occ.commitment.name, amount_cents: occ.commitment.amount_cents,
                due_on: due.iso8601, days_overdue: (@from - due).to_i)
        end
      end
    end

    # No range API exists — occurrences are value objects; CommitmentOccurrence.for_month is
    # the batched (payments-preloaded, no N+1) per-month base. Window + grace spans 1–2 months.
    def occurrences
      months_between(@from - OVERDUE_GRACE_DAYS, @to)
        .flat_map { |month| CommitmentOccurrence.for_month(@account, month) }
    end

    # Fatura closing ("fecha em N dias — X até agora") and due ("vence amanhã") per
    # billing-configured card. closing_date(m) may precede month m by up to 28 days
    # (closing_offset_days), so billing months one past the window are probed too — a date
    # outside the window simply yields nothing.
    def card_events
      @account.credit_cards.kept.roots.select(&:billing_configured?).flat_map do |card|
        months_between(@from, @to >> 1).flat_map { |month| card_bill_events(card, month) }
      end
    end

    # Both kinds carry the composed hub figure (CreditCard#bill_cents: posted rows +
    # unlinked card-commitment projection) — the running total at closing, the bill amount
    # at due. With closing_offset_days = 0 the two dates coincide and both still fire
    # (distinct kinds, distinct copy): that card's fatura closes and falls due at once.
    # A card_due whose month already has a CLOSED bill row carries card_bill_id + the
    # bill's effective total — the pay CTA (.plans/credit-cards 01 §4.3); dedup key
    # unchanged. card_closing fires BEFORE closing, so there is never a row to link.
    def card_bill_events(card, billing_month)
      bill = card.card_bills.find_by(billing_month: billing_month)
      { "card_closing" => card.closing_date(billing_month),
        "card_due"     => card.due_date(billing_month) }.filter_map do |kind, date|
        next unless date.between?(@from, @to)
        payload = { card: card.display_name,
                    amount_cents: card.bill_cents(billing_month),
                    date: date.iso8601, days_until: (date - @from).to_i }
        if kind == "card_due" && bill
          payload[:card_bill_id] = bill.id
          payload[:amount_cents] = bill.effective_total_cents
        end
        event(kind, card, date, **payload)
      end
    end

    # One escalation per closed unpaid bill once past due (.plans/credit-cards phase 3):
    # period_key = the bill's month, so however many mornings re-scan an unpaid bill, the
    # dedup key (kind, card, billing_month) yields ONE row ever. Paid bills never fire;
    # amount = what's still open (partial payments shrink it at snapshot time).
    def card_overdue_events
      @account.card_bills.includes(credit_card: :institution)
              .where(due_on: ...@from).filter_map do |bill|
        card = bill.credit_card
        next if card.soft_deleted? || bill.paid?
        event("card_overdue", card, bill.billing_month,
              card: card.display_name,
              amount_cents: bill.effective_total_cents - bill.paid_cents,
              due_on: bill.due_on.iso8601, card_bill_id: bill.id)
      end
    end

    # Expected incomes whose expected_on falls in the window and that have NOT landed —
    # per MonthSummary#income_received?, which also matches unlinked posted deposits within
    # ±10% on the income's account, so an already-arrived salary never nags.
    def income_events
      months    = months_between(@from, @to)
      summaries = months.index_with { |month| MonthSummary.new(@account, month) }
      @account.incomes.kept.active.flat_map do |income|
        months.filter_map do |month|
          expected = income.expected_on(month)
          next unless expected.between?(@from, @to)
          next if summaries[month].income_received?(income)
          event("income_expected", income, expected,
                name: income.name, amount_cents: income.amount_cents,
                expected_on: expected.iso8601, days_until: (expected - @from).to_i)
        end
      end
    end

    # First-of-month Dates covering [from, to] — 1–2 iterations for any 0–7-day lead.
    def months_between(from, to)
      months, month = [], from.beginning_of_month
      while month <= to.beginning_of_month
        months << month
        month = month >> 1
      end
      months
    end

    def event(kind, subject, period_key, **payload)
      { kind: kind, subject: subject, period_key: period_key, payload: payload }
    end
  end
end
