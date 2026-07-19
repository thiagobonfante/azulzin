# The "Recentes" two-day purchase-date window (.plans/today-expenses). Shared by every
# controller whose turbo streams can land while the user is on /transactions/recent: the page
# threads context=recent (+ the active chip filter) through its forms, the action calls
# load_recent_refresh, and the stream template replaces recent_summary + recent_chips from the
# fresh load — figures, day grouping and empty states honest in one render.
module RecentRefresh
  private
    def load_recent_refresh
      return unless params[:context] == "recent"
      @recent_today    = recent_today
      @recent_window   = recent_window_rows
      @recent_category = recent_category_filter
      @recent_rows     = recent_filter_by_category(@recent_window, @recent_category)
    end

    def recent_today = Date.current.in_time_zone("America/Sao_Paulo").to_date

    # Recents-first within a day (occurred_on is date-only, so created_at breaks the tie).
    def recent_window_rows
      today = recent_today
      Current.account.transactions
             .occurred_between(today - 1, today)
             .includes(:bank_account, :credit_card, :category, :commitment,
                       :transfer_to_bank_account, :receipt_attachment)
             .order(occurred_on: :desc, created_at: :desc, id: :desc)
             .to_a
    end

    # Chip filter (house param posture): :none = uncategorized, a kept own-account Category,
    # or nil = all — garbage and cross-account ids fall back to all.
    def recent_category_filter
      return :none if params[:category] == "none"
      Current.account.categories.kept.find_by(id: params[:category]) if params[:category].present?
    end

    # In-Ruby filter over the loaded window (same posture as the ledger body). :none means
    # uncategorized non-transfer rows — transfers are never categorized, so they'd drown it.
    def recent_filter_by_category(rows, filter)
      case filter
      when :none    then rows.select { |r| r.category_id.nil? && r.direction != "transfer" }
      when Category then rows.select { |r| r.category_id == filter.id }
      else rows
      end
    end
end
