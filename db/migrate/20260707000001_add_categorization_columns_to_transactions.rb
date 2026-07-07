class AddCategorizationColumnsToTransactions < ActiveRecord::Migration[8.0]
  def up
    add_column :transactions, :merchant_norm, :string
    add_column :transactions, :category_source, :string
    add_index  :transactions, [ :account_id, :merchant_norm ]

    # Backfill merchant_norm in Ruby (normalization is I18n.transliterate, not SQL).
    say_with_time "backfilling merchant_norm" do
      Transaction.unscoped.where.not(merchant: [ nil, "" ]).select(:id, :merchant).find_in_batches(batch_size: 500) do |batch|
        batch.group_by { |t| TextMatch.normalize(t.merchant).presence }.each do |norm, rows|
          next unless norm
          Transaction.unscoped.where(id: rows.map(&:id)).update_all(merchant_norm: norm)
        end
      end
    end

    # Provenance backfill: WhatsApp-created rows with a category were categorized by the
    # LLM-guess resolver → "ai". Everything else stays NULL (unknown legacy provenance;
    # deliberately excluded from merchant memory until a human touches it).
    say_with_time "backfilling category_source for WhatsApp rows" do
      Transaction.unscoped.where.not(source_message_id: nil).where.not(category_id: nil)
                 .update_all(category_source: "ai")
    end
  end

  def down
    remove_index  :transactions, [ :account_id, :merchant_norm ]
    remove_column :transactions, :merchant_norm
    remove_column :transactions, :category_source
  end
end
