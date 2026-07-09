# Earmarking (round 3 decision 7): WHERE the "já guardado" head start sits, so the bank
# accounts page can split each caixinha's balance into livre vs guardado-para-meta. Nullable —
# households with no savings account keep the bare-amount behavior; mirrors the caixinha FK.
class AddInitialSavedBankAccountToGoals < ActiveRecord::Migration[8.1]
  def change
    add_reference :goals, :initial_saved_bank_account, null: true,
                  foreign_key: { to_table: :bank_accounts, on_delete: :nullify }
  end
end
