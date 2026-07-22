class AddCardBillPaymentToTransactions < ActiveRecord::Migration[8.0]
  def change
    # The fatura payment is a TRANSFER to the card (.plans/credit-cards 01 §3) — never an
    # expense, or the month would count the spend twice (once in saídas, once in faturas).
    add_reference :transactions, :transfer_to_credit_card, foreign_key: { to_table: :credit_cards }
    add_reference :transactions, :card_bill, index: false, foreign_key: true
    add_index :transactions, :card_bill_id, where: "card_bill_id IS NOT NULL"

    # Widen the dest-only-on-transfer check to both destination columns, and cap at one.
    remove_check_constraint :transactions, name: "transactions_transfer_dest_only_on_transfer"
    add_check_constraint :transactions,
      "(transfer_to_bank_account_id IS NULL AND transfer_to_credit_card_id IS NULL) OR direction = 'transfer'",
      name: "transactions_transfer_dest_only_on_transfer"
    add_check_constraint :transactions,
      "num_nonnulls(transfer_to_bank_account_id, transfer_to_credit_card_id) <= 1",
      name: "transactions_one_transfer_dest_max"
  end
end
