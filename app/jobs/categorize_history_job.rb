# Runs the historical auto-categorization backfill for one account (auto-categories Phase 5).
# Mirrors ProcessDocumentImportJob's posture: serialized per account, daily cap re-checked
# INSIDE the job so a duplicate enqueue never buys a second AI run.
class CategorizeHistoryJob < ApplicationJob
  queue_as :imports

  limits_concurrency to: 1, key: ->(account_id) { account_id }

  retry_on OpenRouterClient::RateLimited, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(account_id)
    account = Account.find(account_id)
    # Daily cap (checked in the controller too; re-checked here against races/duplicates).
    # category_backfill_at is stamped BEFORE the work so it anchors the undo window
    # (rows touched by this run have updated_at >= it and created_at < it).
    return if account.category_backfill_at&.after?(24.hours.ago)

    account.update!(category_backfill_at: Time.current)
    Categories::Backfill.call(account)
  end
end
