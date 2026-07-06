module Whatsapp
  # undo_last intent (07 §4.8) — also reachable from the Interpreter's deterministic pre-pass (0
  # LLM calls). Reverses the last WA-produced row ≤ 24h; an installment fan-out is torn down as a
  # unit; never touches rejected/superseded rows or another user's referent.
  class UndoHandler
    include HandlerHelpers

    def initialize(msg, _extraction = nil)
      @msg = msg
    end

    def call
      row = last_wa_row
      return reply("nothing_to_undo") unless row

      if row.commitment&.installment? && row.installment_number
        teardown(row.commitment)
      else
        row.reverse!
        reply("undone", txn: row, amount: currency(row.amount_cents), merchant: (row.merchant.presence || "—"))
      end
      row
    end

    private

    # "apaga o último" MUST mean *my* last WA row within the account, not whoever texted most
    # recently (spine D6). .kept excludes rows soft-deleted in-app (doc 04 §4.4).
    def last_wa_row
      account.transactions.kept.where(created_by: user).where.not(whatsapp_message_id: nil)
             .where("created_at > ?", 24.hours.ago)
             .where.not(status: %w[rejected superseded]).order(created_at: :desc).first
    end

    def teardown(commitment)
      count      = commitment.installments_count
      parcel     = currency(commitment.amount_cents)
      instrument = commitment.credit_card&.display_name || commitment.bank_account&.display_name
      ActiveRecord::Base.transaction do
        commitment.payments.destroy_all
        commitment.destroy
      end
      reply("undone_installments", count: count, parcel: parcel, instrument: instrument)
    end
  end
end
