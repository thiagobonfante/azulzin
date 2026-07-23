module CardBills
  # Pays (part of) a closed fatura (.plans/credit-cards 01 §3) — the money-correctness
  # core: the payment is a TRANSFER from the source bank account to the card, never an
  # expense (the spend already settles through bills_cents; an expense would count it
  # twice). Source is optional (P0 #4): a payment from an untracked account still records
  # THAT and HOW MUCH was paid, it just moves no tracked balance. Multiple partial
  # payments are legitimate (paid_cents is a sum); unpay = reverse! on the payment row.
  class Pay
    def self.call(bill, amount_cents:, paid_on:, bank_account: nil,
                  stated_total_cents: nil, stated_minimum_cents: nil, created_by: nil)
      stated = { stated_total_cents: stated_total_cents,
                 stated_minimum_cents: stated_minimum_cents }.compact
      bill.update!(stated) if stated.any?

      bill.account.transactions.create!(
        created_by:                 created_by,
        direction:                  "transfer",
        status:                     "posted",
        confirmed_at:               Time.current,
        amount_cents:               amount_cents,
        occurred_on:                paid_on,
        bank_account:               bank_account,
        transfer_to_credit_card_id: bill.credit_card_id,
        card_bill:                  bill,
        merchant:                   bill.credit_card.display_name,
        # Paying July's bill in August must not re-bucket into August.
        billing_month:              bill.billing_month,
        billing_month_manual:       true,
        source:                     "app"
      )
    end
  end
end
