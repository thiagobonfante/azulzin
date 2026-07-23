class RenameEntradaTransactionOnCardBillFinancings < ActiveRecord::Migration[8.1]
  def change
    rename_column :card_bill_financings, :entrada_transaction_id, :down_payment_transaction_id
  end
end
