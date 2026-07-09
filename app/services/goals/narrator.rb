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
      narratives.merge("fp" => Goals.plan_fingerprint(@build))   # invalidates if the plans change later
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

      # Whole-real (ceil) so the coach note figures match the plan-card UI (round 3 P1).
      def fmt(cents) = WhatsappReply.currency(cents, locale: @locale, whole: true)

      # No money figure and no large number may appear that wasn't in the pre-formatted inputs.
      # Money is matched as a full joined-digit figure (so "R$ 5.000" can't hide behind an existing
      # "…000"); other numbers must match a whole input run, except ≤2-digit counts ("3 meses").
      def digits_ok?(narratives)
        allowed_money = money_figures(plan_lines.to_json)
        allowed_runs  = number_runs(plan_lines.to_json)
        narratives.all? do |n|
          (money_figures(n) - allowed_money).empty? &&
            number_runs(n).all? { |run| run.length <= 2 || allowed_runs.include?(run) }
        end
      end

      def money_figures(str) = str.to_s.scan(/R\$\s?[\d.,]+/).map { |t| t.scan(/\d/).join }
      def number_runs(str)   = str.to_s.scan(/\d+/)
  end
end
