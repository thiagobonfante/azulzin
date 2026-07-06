module Installments
  # Fans out a card installment purchase (R11) into N eager POSTED parcels riding future bills,
  # under one Commitment(kind: "installment") parent. Called by both the in-app form and the
  # WhatsApp decider. Idempotent on the parent's source_message_id. See 02 §4 / 01 §6.
  class Create
    def self.call(account:, created_by:, card:, total_cents:, count:, occurred_on:, merchant:,
                  category_id: nil, source_message_id: nil, whatsapp_message: nil)
      # Idempotency finder stays unscoped by soft delete (source_message_id replay must no-op).
      if source_message_id && (existing = account.commitments.find_by(source_message_id: source_message_id))
        return existing # replay ⇒ zero new rows
      end

      first_bill = card.billing_month_for(occurred_on)
      amounts    = split_cents(total_cents, count)

      ActiveRecord::Base.transaction do
        commitment = account.commitments.create!(
          created_by: created_by,   # explicit: this may run in a WhatsApp job (Current is nil)
          credit_card: card, name: merchant.presence || I18n.t("commitments.default_installment_name"),
          kind: "installment", amount_cents: amounts.first, total_cents: total_cents,
          installments_count: count, schedule_kind: "fixed_day", schedule_day: nil,
          starts_on: first_bill, source: (source_message_id ? "whatsapp" : "app"),
          source_message_id: source_message_id, category_id: category_id
        )
        amounts.each_with_index do |cents, i|
          account.transactions.create!(
            created_by: created_by,
            commitment: commitment, credit_card: card, direction: "expense", status: "posted",
            payment_method: "credito", confirmed_at: Time.current, amount_cents: cents,
            occurred_on: occurred_on, merchant: merchant, installment_number: i + 1,
            billing_month: first_bill >> i, billing_month_manual: false,
            category_id: category_id, whatsapp_message: whatsapp_message
          )
        end
        commitment
      end
    end

    # Deterministic centavo split (09 P0 #5): the first (total % count) parcels get the extra
    # centavo. Parcels never differ by more than one; the sum is exact.
    def self.split_cents(total, count)
      base = total / count
      remainder = total % count
      Array.new(count) { |i| i < remainder ? base + 1 : base }
    end
  end
end
