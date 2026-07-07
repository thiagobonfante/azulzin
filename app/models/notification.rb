# One spine row = the dashboard alert + the WhatsApp send-claim + the dedup key
# (.plans/up-tier 01 §1). Rows are per MEMBER (the recipient) but about ACCOUNT data.
# The unique index (index_notifications_dedup) is the idempotency referee — scanners
# re-run freely and never double-notify; `payload` snapshots everything both renderers
# need, so a deleted subject still renders.
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :subject, polymorphic: true, optional: true   # nil for summaries

  validates :kind, inclusion: { in: Notifications::KINDS.keys }
  validates :period_key, presence: true

  # Dashboard surface (01 §4): the member's live alerts in their current account, newest first.
  scope :undismissed,   -> { where(dismissed_at: nil) }
  scope :newest_first,  -> { order(created_at: :desc) }
  scope :dashboard_for, ->(user, account) { where(user: user, account: account).undismissed.newest_first }

  # Idempotent insert on the dedup keys (user, kind, subject, period_key). A re-running
  # scanner gets the existing row back untouched — NEVER clobbering whatsapp_sent_at,
  # dismissed_at, or payload (the goals lesson: no find_or_initialize-overwrite). The
  # unique index referees the race: a concurrent loser rescues RecordNotUnique and loads
  # the winner's row. The payload is stringified at the door so the in-memory row is
  # indistinguishable from a reloaded one — scanners build symbol-keyed events, consumers
  # (template_key, template_args) read string keys.
  def self.record!(user:, account:, kind:, period_key:, subject: nil, payload: {})
    dedup = { user: user, kind: kind, subject: subject, period_key: period_key }
    find_or_create_by!(dedup) do |notification|
      notification.account = account
      notification.payload = payload.deep_stringify_keys
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(dedup)
  end

  def dismiss! = update!(dismissed_at: Time.current)
end
