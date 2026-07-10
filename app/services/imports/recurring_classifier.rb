require "json"

# The 2nd LLM stage (§6.1) — one call per document, for ALL formats (it's the only LLM call
# CSV/OFX make). Input is COMPACT normalized rows (never the raw document): {id, date,
# description, amount, signals}. The LLM labels each row and names the merchant/commitment; Ruby
# respects the deterministic signals and builds proposals. `client:` is injectable for tests.
module Imports
  module RecurringClassifier
    module_function

    SYSTEM_PROMPT = <<~PT.freeze
      Você classifica linhas de um extrato ou fatura brasileira para descobrir o que é
      recorrente na vida financeira da pessoa. Não invente.
      Para cada linha (id preservado), devolva:
      - label: subscription (assinatura: Netflix, Google One...), fixed_bill (conta fixa:
        aluguel, luz, água, telefone, seguro, financiamento, mensalidade), installment
        (Parcela NN/MM), income (salário ou recebimento recorrente), transfer (entre contas
        da própria pessoa), one_off (compra/pix avulso) ou noise (tarifas, rendimentos,
        ajustes sem significado para o orçamento).
      - Os signals já detectados pelo app vêm em cada linha: respeite-os. Uma linha com signal
        installment_counter é installment; known_subscription é subscription. Sua tarefa
        principal são as linhas SEM signal.
      - merchant_canonical: o nome limpo do estabelecimento ("DL*GOOGLE GOOGLE" → "Google").
      - commitment_name: um nome curto em português para o compromisso ("Aluguel", "Energia
        (Copel)", "Google One", "Seguro incêndio"); null se label for one_off/noise/transfer.
      - category_guess: um palpite de categoria em português ("moradia", "assinaturas"); será
        resolvido no app, nunca invente um identificador.
      - schedule_day: o dia do mês provável da cobrança (o dia observado); null se não fizer sentido.
      - confidence de 0 a 1 por linha: quão certa é a classificação COM a evidência dada. Uma
        única ocorrência de algo que parece salário ainda é incerta — seja honesto.
    PT

    SCHEMA = {
      name: "import_recurring_classification",
      schema: {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[rows],
        "properties" => { "rows" => { "type" => "array", "items" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[id label merchant_canonical commitment_name category_guess schedule_day confidence],
          "properties" => {
            "id"                 => { "type" => "integer" },
            "label"              => { "type" => "string",
                                      "enum" => %w[subscription fixed_bill installment income transfer one_off noise] },
            "merchant_canonical" => { "type" => %w[string null] },
            "commitment_name"    => { "type" => %w[string null] },
            "category_guess"     => { "type" => %w[string null] },
            "schedule_day"       => { "type" => %w[integer null] },
            "confidence"         => { "type" => "number" } } } } }
      }
    }.freeze

    # A whole extrato's labels in one response can blow the output cap and truncate the JSON —
    # which used to silently classify EVERY row one_off. Batch the rows instead.
    BATCH_SIZE = 80

    # rows: the §8 normalized rows (post-exclusion). Returns the LLM row objects, id-indexed by the
    # caller (ids are global across batches). Rows the LLM drops default to one_off/0 downstream.
    # `account` adds the closed-set category line so category_guess answers inside the user's own
    # taxonomy.
    def call(rows, account: nil, client: nil)
      return [] if rows.empty?

      client ||= OpenRouterClient.new(task: :import_extraction)
      category_line = Categories.closed_set_line(account, field: "category_guess")
      rows.each_slice(BATCH_SIZE).with_index.flat_map do |batch, index|
        user_content = [ compact(batch, offset: index * BATCH_SIZE).to_json, category_line ].compact.join("\n\n")
        messages = [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: user_content }
        ]
        parsed = client.chat(messages: messages, schema: SCHEMA).parsed
        raise Imports::ParseError, "unparseable classification" if parsed.nil?

        Array(parsed["rows"])
      end
    end

    def compact(rows, offset: 0)
      rows.each_with_index.map do |row, id|
        { "id" => offset + id, "date" => row["date"], "description" => row["description"],
          "amount" => signed_decimal(row), "signals" => Array(row["signals"]) }
      end
    end

    def signed_decimal(row)
      cents = row["amount_cents"].to_i
      sign  = row["direction"] == "out" ? "-" : ""
      format("%s%d.%02d", sign, cents / 100, cents % 100)
    end
  end
end
