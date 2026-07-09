# Onboarding via document upload (.plans/auto, D2): the ONE new table. The uploaded blob
# rides Active Storage (has_one_attached :file); fingerprint + extraction + proposals are
# jsonb. `extraction` (raw parse output, financial PII) is purged 30 days after a terminal
# status; fingerprint/proposals/checksum survive the purge.
class CreateDocumentImports < ActiveRecord::Migration[8.1]
  def change
    create_table :document_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :status, null: false, default: "uploaded"
      # uploaded | processing | extracted | failed | applied | dismissed
      t.string     :kind          # bank_statement | card_bill | unknown — nil until classified
      t.string     :source_format # csv | ofx | pdf — nil until detected
      t.references :institution, foreign_key: true # resolved in Ruby, never by the LLM
      t.jsonb      :fingerprint, null: false, default: {}
      t.jsonb      :extraction,  null: false, default: {} # normalized parse output — PURGED at 30d
      t.jsonb      :proposals,   null: false, default: [] # proposal objects — survives purge
      t.string     :error_code
      t.string     :checksum, null: false # SHA256 hex of the raw blob bytes
      t.timestamps

      t.index %i[user_id status]
      # Per-user, partial dedupe: a live import (uploaded/processing/extracted/applied) blocks a
      # re-upload of the same bytes; a dismissed/failed one does not (retry after a fix must work).
      t.index %i[user_id checksum], unique: true,
              where: "status NOT IN ('dismissed', 'failed')",
              name: "index_document_imports_dedupe_checksum"
    end
  end
end
