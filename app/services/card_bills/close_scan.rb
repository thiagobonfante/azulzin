module CardBills
  # Materializes closed bills (.plans/credit-cards 01 §2). Daily via CloseScanJob, and
  # lazily from the bill-page/cards-page entry points (ensure_for) so a user arriving
  # minutes after closing sees a payable bill before the morning run. Idempotent by the
  # [credit_card_id, billing_month] unique index.
  class CloseScan
    def self.call(account)
      account.credit_cards.kept.select(&:billing_configured?).flat_map { |card| ensure_for(card) }
    end

    # With no rows yet only the most recently closed month materializes — history before
    # ship day stays query-only (no backfill migration); once a row exists, the catch-up
    # loop covers scan gaps without duplicates and without touching the open month.
    def self.ensure_for(card)
      return [] unless card.billing_configured?
      open_month = card.current_open_bill_month
      last  = card.card_bills.maximum(:billing_month)
      month = last ? (last >> 1) : (open_month << 1)
      bills = []
      while month < open_month
        bills << close(card, month)
        month = month >> 1
      end
      bills.compact
    end

    def self.close(card, month)
      return nil if card.bill_cents(month) <= 0   # P0 #1: zero bills — no row, no notification
      CardBill.create_or_find_by!(credit_card: card, billing_month: month) do |bill|
        bill.account   = card.account
        bill.closed_on = card.closing_date(month)
        bill.due_on    = card.due_date(month)
      end
    end
  end
end
