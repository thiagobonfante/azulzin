module Whatsapp
  # move_bill intent ("joga pra próxima fatura"): moves the sender's last simple WA card
  # purchase to another fatura. The month is deterministic (MonthPhrase — the LLM only hands
  # over the words); the move is the sticky manual override assign_billing_month respects.
  class MoveBillHandler
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      row = last_wa_row
      return reply("nothing_to_move") unless row
      return reply("move_not_card") unless row.credit_card

      target = MonthPhrase.parse(@extraction.target_bill_raw, reference: row.billing_month)
      # ponytail: a bare "joga pra outra fatura" parses to the row's own month — "move" means
      # move, so default to the next fatura. v1.1: whole installment-plan moves.
      target = row.billing_month >> 1 if target == row.billing_month

      row.updated_by = user   # explicit: job context, Attributable's Current.user hook is nil (doc 04 §5)
      row.update!(billing_month: target, billing_month_manual: true)
      reply("bill_moved", txn: row, amount: currency(row.amount_cents),
            merchant: (row.merchant.presence || "—"), month: month_label(target))
      row
    end

    private

    # Same referent doctrine as edit_last: the sender's own last WA row within the account
    # (spine D6), .kept, ≤ 24h, simple rows only — a parcel is never moved alone.
    def last_wa_row
      account.transactions.kept.where(created_by: user).where.not(whatsapp_message_id: nil)
             .where("created_at > ?", 24.hours.ago)
             .where.not(status: %w[rejected superseded]).where(installment_number: nil)
             .order(created_at: :desc).first
    end
  end
end
