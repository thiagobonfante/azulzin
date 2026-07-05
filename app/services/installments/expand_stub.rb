module Installments
  # In-app confirm of a low-confidence WhatsApp installment stub (07 §4.4): fans out the real
  # plan from the data parked in the stub's `extraction` jsonb and supersedes the stub — so a
  # single parked row becomes N parcels (card) or a debit Commitment. Claims the stub with a
  # guarded transition first, so a double-confirm can never expand twice. Returns the created
  # Commitment, or nil when the stub can't be expanded (no count, no instrument, no amount).
  class ExpandStub
    def self.call(transaction)
      data  = transaction.extraction || {}
      count = data["installments_count"].to_i
      return nil unless count.between?(2, 48)

      instrument = transaction.credit_card || transaction.bank_account || resolve_instrument(transaction, data)
      return nil unless instrument

      total = derive_total(data, count) || transaction.amount_cents
      return nil unless total&.positive?

      commitment = nil
      ActiveRecord::Base.transaction do
        # Claim the stub (superseded) before creating rows — a concurrent confirm finds it
        # already superseded and rolls back with no plan created.
        raise ActiveRecord::Rollback unless transaction.guarded_update(Transaction::PENDING_INBOX_STATUSES, status: "superseded")
        commitment = build_plan(transaction, instrument, total, count)
      end
      commitment
    end

    def self.build_plan(transaction, instrument, total, count)
      if instrument.is_a?(CreditCard)
        Installments::Create.call(user: transaction.user, card: instrument, total_cents: total, count: count,
          occurred_on: transaction.occurred_on, merchant: transaction.merchant, category_id: transaction.category_id)
      else
        transaction.user.commitments.create!(
          bank_account: instrument, name: transaction.merchant.presence || I18n.t("commitments.default_installment_name"),
          kind: "installment", amount_cents: (total.to_f / count).round, total_cents: total, installments_count: count,
          schedule_kind: "fixed_day", schedule_day: transaction.occurred_on.day,
          starts_on: transaction.occurred_on.beginning_of_month, source: "app", category_id: transaction.category_id
        )
      end
    end

    def self.derive_total(data, count)
      if data["installment_total_raw"].present?
        Money.to_cents(data["installment_total_raw"])
      elsif data["installment_parcel_raw"].present?
        Money.to_cents(data["installment_parcel_raw"]).to_i * count
      end
    end

    def self.resolve_instrument(transaction, data)
      return nil if data["instrument_phrase"].blank?
      ex = Whatsapp::Extraction.new(instrument_phrase: data["instrument_phrase"],
                                    payment_method: data["payment_method"] || "desconhecido")
      result = Whatsapp::Matcher.new(transaction.user, ex).call
      result.instrument if result.matched?
    end
  end
end
