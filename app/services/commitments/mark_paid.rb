module Commitments
  # Marks a (debit) commitment occurrence paid: one posted Transaction, shared verbatim by the
  # hub's Pagar button and the WhatsApp "paguei o carro" intent. billing_month is set explicitly
  # (manual) so a past-month catch-up is never re-bucketed into today's month. Double-pay is
  # race-safe at the DB (paid-once index); the rescue turns it into a friendly no-op. 01 §6 / 05 §5.5.
  class MarkPaid
    def self.call(commitment, month, amount: nil, source_message_id: nil, whatsapp_message: nil)
      month = month.beginning_of_month
      txn = commitment.user.transactions.new(
        commitment:           commitment,
        merchant:             commitment.name,
        direction:            "expense",
        status:               "posted",
        confirmed_at:         Time.current,
        amount_cents:         amount || commitment.amount_cents,
        category_id:          commitment.category_id,
        occurred_on:          Date.current.in_time_zone("America/Sao_Paulo").to_date,
        billing_month:        month,
        billing_month_manual: true,
        source:               (source_message_id ? "whatsapp" : "app"),
        source_message_id:    source_message_id,
        whatsapp_message:     whatsapp_message
      )
      txn.installment_number = commitment.installment_no(month) if commitment.installment?
      copy_instrument(txn, commitment)
      txn.save!
      txn
    rescue ActiveRecord::RecordNotUnique
      commitment.payments.posted.find_by(billing_month: month) # already paid → return the existing row
    end

    def self.copy_instrument(txn, commitment)
      if commitment.credit_card_id
        txn.credit_card_id = commitment.credit_card_id
      else
        txn.bank_account_id = commitment.bank_account_id
      end
    end
  end
end
