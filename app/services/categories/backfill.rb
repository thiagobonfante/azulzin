module Categories
  # Historical backfill (auto-categories Phase 5): categorize the account's uncategorized
  # posted expenses. Memory pass first (free, deterministic), then batched closed-set LLM
  # calls. Applied silently (decision O3) — every row stays editable in the ledger and the
  # whole run is undoable via the category_backfill_at window. Only ever touches rows whose
  # category_id IS NULL, so a re-run is a no-op for already-categorized rows.
  class Backfill
    BATCH_SIZE   = 100
    MAX_LLM_ROWS = 2_000  # per run; the daily cap means the tail waits for tomorrow

    SYSTEM_PROMPT = <<~PT.freeze
      Você categoriza gastos de um histórico financeiro brasileiro. Para cada linha
      (id preservado), devolva category = o nome de categoria fornecido que melhor descreve
      o gasto, ou null se nenhum servir. Não invente nomes nem identificadores.
    PT

    SCHEMA = {
      name: "category_backfill",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[rows],
        "properties" => { "rows" => { "type" => "array", "items" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[id category],
          "properties" => {
            "id"       => { "type" => "integer" },
            "category" => { "type" => %w[string null] } } } } }
      }
    }.freeze

    # → number of rows categorized. `client:` injectable for tests.
    def self.call(account, client: nil) = new(account, client: client).call

    def initialize(account, client: nil)
      @account = account
      @client  = client
    end

    def call
      memory_pass + llm_pass
    end

    private

    def scope
      @account.transactions.kept.posted.where(direction: "expense", category_id: nil)
    end

    def stamp(relation, category_id, source)
      relation.update_all(category_id: category_id, category_source: source, updated_at: Time.current)
    end

    def memory_pass
      scope.where.not(merchant_norm: nil).distinct.pluck(:merchant_norm).sum do |norm|
        result = Suggest.call(account: @account, merchant: norm)
        result ? stamp(scope.where(merchant_norm: norm), result.category.id, "memory") : 0
      end
    end

    def llm_pass
      closed_set = Categories.closed_set_line(@account)
      return 0 unless closed_set

      rows = scope.order(occurred_on: :desc).limit(MAX_LLM_ROWS).pluck(:id, :merchant, :description, :amount_cents)
      return 0 if rows.empty?

      client = @client || OpenRouterClient.new(task: :category_backfill)
      rows.each_slice(BATCH_SIZE).sum { |batch| categorize_batch(client, closed_set, batch) }
    end

    # Batch-local ids (0..99), never DB ids: a hallucinated id can at worst hit another row
    # of the same batch, and the compact rows stay small.
    def categorize_batch(client, closed_set, batch)
      compact = batch.each_with_index.map do |(_id, merchant, description, cents), i|
        { "id" => i, "merchant" => merchant, "description" => description,
          "amount" => format("%d.%02d", cents.to_i / 100, cents.to_i % 100) }
      end
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: [ compact.to_json, closed_set ].join("\n\n") }
      ]
      parsed = client.chat(messages: messages, schema: SCHEMA).parsed || {}
      Array(parsed["rows"]).sum do |row|
        txn_id = batch.dig(row["id"].to_i, 0)
        category = Resolve.call(account: @account, label: row["category"])
        # scope re-check keeps this idempotent: a row categorized meanwhile is left alone.
        (txn_id && category) ? stamp(scope.where(id: txn_id), category.id, "ai") : 0
      end
    end
  end
end
