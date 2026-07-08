module Goals
  # Touchpoint 2 (.plans/goals 04 §2): ONE closed-set call labels the account's custom categories
  # flexible/essential, writing categories.flexibility. Only categories unmatched by the seeded-name
  # map AND not yet cached are sent — paid once per category name, EVER, so it amortizes to ~0 and is
  # exempt from the session quota (structurally bounded). Mirrors Categories::Backfill. Injectable client.
  class CategoryClassifier
    SCHEMA = {
      name: "goals_classify",
      schema: {
        "type" => "object", "additionalProperties" => false, "required" => %w[categories],
        "properties" => { "categories" => { "type" => "array", "items" => {
          "type" => "object", "additionalProperties" => false, "required" => %w[name flexibility],
          "properties" => { "name" => { "type" => "string" },
                            "flexibility" => { "type" => "string", "enum" => %w[flexible essential] } } } } }
      }
    }.freeze

    SYSTEM_PROMPT = <<~PT.freeze
      Classifique cada categoria de gasto brasileira como "flexible" (discricionário — dá para
      cortar sem crise: lazer, restaurantes, compras) ou "essential" (fixo/necessário: moradia,
      contas, saúde, transporte). Devolva o mesmo nome fornecido, sem inventar categorias.
    PT

    def self.call(account, client: nil) = new(account, client:).call

    def initialize(account, client: nil)
      @account = account
      @client  = client
    end

    # → number of categories classified (0 when all are name-matched or already cached ⇒ no LLM call).
    def call
      pending = @account.categories.kept.where(flexibility: nil)
                        .reject { |c| NAME_FLEXIBILITY.key?(c.name.to_s.downcase) }
      return 0 if pending.empty?

      parsed = client.chat(messages: messages(pending), schema: SCHEMA).parsed || {}
      by_name = Array(parsed["categories"]).to_h { |h| [ h["name"], h["flexibility"] ] }
      pending.sum do |cat|
        flex = by_name[cat.name]
        next 0 unless %w[flexible essential].include?(flex)
        cat.update!(flexibility: flex)
        1
      end
    rescue OpenRouterClient::Error
      0
    end

    private
      def client = @client || OpenRouterClient.new(task: :goals_classify)

      def messages(pending)
        [ { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: pending.map(&:name).to_json } ]
      end
  end
end
