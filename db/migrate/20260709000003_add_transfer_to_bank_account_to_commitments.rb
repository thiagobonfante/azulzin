# Standalone savings commitments (round 3 P4): WHERE a goal-less "Guardar" contribution lands.
# Goal-backed savings keep the destination on the goal (this stays nil there — no backfill);
# installment/fixed/subscription never set it. Column name mirrors the transactions transfer leg.
class AddTransferToBankAccountToCommitments < ActiveRecord::Migration[8.1]
  def change
    add_reference :commitments, :transfer_to_bank_account, null: true,
                  foreign_key: { to_table: :bank_accounts }
  end
end
