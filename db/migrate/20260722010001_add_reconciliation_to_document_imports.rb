class AddReconciliationToDocumentImports < ActiveRecord::Migration[8.0]
  def change
    # document_imports IS the reconciliation run record (.plans/credit-cards 03 §3): same
    # lifecycle, guards and attachments — purpose branches the tail of the pipeline.
    add_column :document_imports, :purpose, :string, null: false, default: "onboarding"
    add_reference :document_imports, :credit_card, foreign_key: true
    add_reference :document_imports, :bank_account, foreign_key: true
    add_column :document_imports, :period, :date

    add_check_constraint :document_imports,
      "purpose <> 'reconciliation' OR num_nonnulls(credit_card_id, bank_account_id) = 1",
      name: "document_imports_reconciliation_target"
  end
end
