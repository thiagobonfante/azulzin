module Goals
  # Enqueued at goal creation to label any custom categories (.plans/goals 04 §2). Exempt from the
  # session quota — it's once-per-category-ever and writes the cache, so subsequent analyses read
  # categories.flexibility with no further calls. A no-op when everything is name-matched or cached.
  class ClassifyJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(account_id)
      Goals::CategoryClassifier.call(Account.find(account_id))
    end
  end
end
