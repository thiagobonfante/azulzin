# Notifications are not an inbox to manage — they auto-expire (.plans/up-tier 01 §4):
# rows whose period_key is well past get deleted daily, keeping the dashboard surface
# query a small index scan. Safe for dedup: scanners only ever look at current periods,
# so a deleted old row can never re-fire. Scheduled via recurring.yml, alongside the
# other 4am retention jobs. Window: ENV NOTIFICATION_RETENTION_DAYS, default 45.
class NotificationRetentionJob < ApplicationJob
  queue_as :background

  DEFAULT_RETENTION_DAYS = 45

  def perform(retain_days: nil)
    cutoff = (retain_days || self.class.retention_days).days.ago.to_date
    purged = Notification.where(period_key: ...cutoff).delete_all
    Rails.logger.info("NotificationRetentionJob deleted #{purged} notifications with period_key before #{cutoff}")
    purged
  end

  def self.retention_days = (ENV["NOTIFICATION_RETENTION_DAYS"].presence || DEFAULT_RETENTION_DAYS).to_i
end
