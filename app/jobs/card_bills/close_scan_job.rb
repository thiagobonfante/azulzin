module CardBills
  # Daily close scan (recurring.yml `card_bills_close`), before reminders_daily_dispatch
  # so the same morning's card_due reminder can link the fresh bill.
  class CloseScanJob < ApplicationJob
    queue_as :default

    def perform
      Account.find_each { |account| CloseScan.call(account) }
    end
  end
end
