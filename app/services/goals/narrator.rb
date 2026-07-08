module Goals
  # Touchpoint 1 (.plans/goals 04 §1): ONE LLM call phrases all 3 plan coach notes. The model
  # NEVER computes — it receives pre-formatted localized money/dates and only phrases the trade-off.
  # A digit-mismatch guard rejects any output that introduces a money figure not in the inputs, so a
  # hallucinated number can never reach the user (template notes stand). Injectable client for tests.
  class Narrator
    SCHEMA = {
      name: "goals_narrative",
      schema: {
        "type" => "object", "additionalProperties" => false, "required" => %w[plans],
        "properties" => { "plans" => { "type" => "array", "items" => {
          "type" => "object", "additionalProperties" => false, "required" => %w[key narrative],
          "properties" => { "key" => { "type" => "string", "enum" => %w[leve recomendado acelerado] },
                            "narrative" => { "type" => "string" } } } } }
      }
    }.freeze

    SYSTEM_PROMPT = <<~PT.freeze
      Você é um coach financeiro do azulzin. Para cada plano (leve, recomendado, acelerado),
      escreva UMA frase curta, honesta e amigável explicando o trade-off em linguagem do dia a dia
      — sem jargão financeiro, sem exclamação exagerada, sem prometer nada. Use APENAS os valores
      já fornecidos (mensal, mês de chegada, cortes); NÃO invente números. Devolva a chave (key) de
      cada plano exatamente como recebida.
    PT

    def self.call(goal, client: nil)
      build = Recompute.call(goal)
      return nil unless build.feasible?
      new(goal, build, client:).call
    end

    def initialize(goal, build, client:)
      @goal = goal
      @build = build
      @client = client
      @locale = (goal.created_by&.locale.presence || I18n.default_locale).to_s
    end

    def call
      parsed = client.chat(messages: messages, schema: SCHEMA).parsed
      return nil unless parsed
      narratives = Array(parsed["plans"]).to_h { |h| [ h["key"], h["narrative"].to_s ] }
                        .slice("leve", "recomendado", "acelerado")
      return nil unless narratives.size == 3 && digits_ok?(narratives.values)
      narratives
    rescue OpenRouterClient::Error
      nil   # any terminal failure → template notes stand
    end

    private
      def client = @client || OpenRouterClient.new(task: :goals_narrative)

      def messages
        [ { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: plan_lines.to_json } ]
      end

      # Pre-formatted, localized — the model sees strings, never cents.
      def plan_lines
        @plan_lines ||= @build.plans.map do |p|
          { "key" => p.template, "mensal" => fmt(p.monthly_target_cents),
            "chega" => (@goal.purchase? && p.projected_done_on ? I18n.l(p.projected_done_on, format: :month_year) : nil),
            "cortes" => p.cuts.map { |c| "#{fmt(c.cut_cents)} em #{c.name}" }.presence }
        end
      end

      def fmt(cents) = WhatsappReply.currency(cents, locale: @locale)

      # The only money figures the narrative may contain are the ones we passed in.
      def digits_ok?(narratives)
        allowed = money_digits(plan_lines.to_json)
        narratives.all? { |n| (money_digits(n) - allowed).empty? }
      end

      def money_digits(str)
        str.to_s.scan(/R\$\s?[\d.,]+/).map { |t| t.scan(/\d/).join }
      end
  end
end
