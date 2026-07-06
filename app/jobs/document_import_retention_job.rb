# Financial PII hygiene (.plans/auto, D8): statements/faturas are purged 30 days after the
# import reaches a terminal status (applied/dismissed/failed). What the product needs long-term
# lives in fingerprint/proposals/checksum, which survive. `extracted` imports are NOT purged —
# their review is still pending (the Pendências nudge). Mirrors WhatsappRetentionJob.
class DocumentImportRetentionJob < ApplicationJob
  queue_as :imports
  DEFAULT_RETENTION_DAYS = 30

  def perform(retain_days: nil)
    cutoff = (retain_days || self.class.retention_days).days.ago
    purged = 0
    DocumentImport.where(status: %w[applied dismissed failed])
                  .where(updated_at: ..cutoff).find_each do |import|
      had = import.file.attached? || import.extraction.present?
      import.file.purge if import.file.attached?
      import.update_columns(extraction: {}) if import.extraction.present? # rubocop:disable Rails/SkipsModelValidations
      purged += 1 if had
    end
    Rails.logger.info("DocumentImportRetentionJob purged blob/extraction for #{purged} imports older than #{cutoff.to_date}")
    purged
  end

  def self.retention_days = (ENV["DOCUMENT_IMPORT_RETENTION_DAYS"].presence || DEFAULT_RETENTION_DAYS).to_i
end
