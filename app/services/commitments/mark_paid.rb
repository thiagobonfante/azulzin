module Commitments
  # Marks a (debit) commitment occurrence paid: one posted Transaction, shared verbatim by the
  # hub's Pagar button and the WhatsApp "paguei o carro" intent. billing_month is set explicitly
  # (manual) so a past-month catch-up is never re-bucketed into today's month. Double-pay is
  # race-safe at the DB (paid-once index); the rescue turns it into a friendly no-op. 01 §6 / 05 §5.5.
  class MarkPaid
    def self.call(commitment, month, amount: nil, created_by: nil, source_message_id: nil, whatsapp_message: nil)
      month = month.beginning_of_month
      txn = commitment.account.transactions.new(
        created_by:           created_by,   # WhatsApp passes msg.user; in-app passes nothing (callback stamps)
        commitment:           commitment,
        merchant:             commitment.name,
        direction:            "expense",
        status:               "posted",
        confirmed_at:         Time.current,
        amount_cents:         amount || commitment.amount_cents,
        category_id:          commitment.category_id,
        # Provenance for merchant memory: app-created commitments had their category picked or
        # confirmed by a person ("user"); WhatsApp-created ones were AI-resolved ("ai").
        category_source:      (commitment.category_id ? (commitment.source == "whatsapp" ? "ai" : "user") : nil),
        occurred_on:          Date.current.in_time_zone("America/Sao_Paulo").to_date,
        billing_month:        month,
        billing_month_manual: true,
        source:               (source_message_id ? "whatsapp" : "app"),
        source_message_id:    source_message_id,
        whatsapp_message:     whatsapp_message
      )
      txn.installment_number = commitment.installment_no(month) if commitment.installment?
      copy_instrument(txn, commitment)
      as_savings_transfer(txn, commitment) if commitment.savings?
      txn.save!
      txn
    rescue ActiveRecord::RecordNotUnique
      commitment.payments.posted.kept.find_by(billing_month: month) # already paid → return the existing row
    end

    # "Pay yourself first" (.plans/goals 07 §1.2): paying a savings commitment is a TRANSFER into
    # the goal's caixinha, never an expense — so it lands in guardado and leaves sobra invariant.
    # bank_account_id (the source) was already set by copy_instrument.
    def self.as_savings_transfer(txn, commitment)
      txn.direction = "transfer"
      txn.category_id = nil
      txn.category_source = nil
      txn.transfer_to_bank_account_id = commitment.goal&.bank_account_id
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
