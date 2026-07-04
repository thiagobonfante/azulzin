# LGPD hygiene: financial audio/photos and transcripts are sensitive. After a grace window
# we purge the heavy/sensitive payload (the media attachment + the stored transcript) while
# keeping the lightweight message + transaction rows for audit. Scheduled via recurring.yml.
# Window: ENV WHATSAPP_RETENTION_DAYS, default 60. See .plans/whats §8.
class WhatsappRetentionJob < ApplicationJob
  queue_as :whatsapp

  DEFAULT_RETENTION_DAYS = 60

  def perform(retain_days: nil)
    cutoff = (retain_days || self.class.retention_days).days.ago
    purged = 0
    WhatsappMessage.where(created_at: ..cutoff).find_each do |msg|
      had = msg.media.attached? || msg.transcription.present?
      msg.media.purge if msg.media.attached?
      msg.update_columns(transcription: nil) if msg.transcription.present?
      purged += 1 if had
    end
    Rails.logger.info("WhatsappRetentionJob purged media/transcripts for #{purged} messages older than #{cutoff.to_date}")
    purged
  end

  def self.retention_days = (ENV["WHATSAPP_RETENTION_DAYS"].presence || DEFAULT_RETENTION_DAYS).to_i
end
