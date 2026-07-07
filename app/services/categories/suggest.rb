module Categories
  # Merchant memory: suggest a category from the account's own history for the same
  # normalized merchant. Deterministic and LLM-free. Reads ONLY human-categorized rows
  # (category_source: "user") — machine-assigned rows never feed the memory, so model
  # mistakes cannot fossilize into a feedback loop.
  class Suggest
    LOOKBACK  = 20    # most recent human-categorized same-merchant rows considered
    MIN_SHARE = 0.6   # modal category must hold at least this share to fire

    Result = Struct.new(:category, :share, :sample_size)

    # → Result or nil. Pure read; persists nothing.
    def self.call(account:, merchant:)
      norm = TextMatch.normalize(merchant).presence
      return nil unless norm

      category_ids = account.transactions.kept
                            .where(merchant_norm: norm, category_source: "user")
                            .where.not(category_id: nil)
                            .order(occurred_on: :desc)
                            .limit(LOOKBACK)
                            .pluck(:category_id)
      return nil if category_ids.empty?

      modal_id, count = category_ids.tally.max_by { |_, n| n }
      share = count.to_f / category_ids.size
      return nil if share < MIN_SHARE

      category = account.categories.kept.find_by(id: modal_id)
      category && Result.new(category, share, category_ids.size)
    end
  end
end
