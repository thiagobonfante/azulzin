class AddEntradaToCardBillFinancings < ActiveRecord::Migration[8.0]
  def change
    # The entrada payment the financing form posted, so cancel can reverse it too
    # (founder 2026-07-22f: unfinance rolls back EVERYTHING the form did). Nullify on
    # hard delete — the LGPD cascade destroys transactions after the bills/financings,
    # but a row deleted alone must not strand the FK.
    add_reference :card_bill_financings, :entrada_transaction,
                  foreign_key: { to_table: :transactions, on_delete: :nullify }
  end
end
