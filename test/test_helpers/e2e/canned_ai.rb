module E2E
  # Deterministic stand-ins for the LLM boundary: builds real Whatsapp::Extraction structs
  # (the LLM only ever classifies — all money math stays in Ruby, same as production).
  # Consumed via E2E::Helpers#with_canned_ai. See .plans/e2e/01 §6.
  module CannedAI
    module_function

    def expense(cents:, merchant:, method: "credito", instrument: nil, category: nil,
                confidence: 0.9, amount_confidence: 0.95, occurred_on: nil, modality: "text")
      base(intent: "expense", intent_confidence: confidence,
           amount_cents: cents, merchant: merchant, payment_method: method,
           instrument_phrase: instrument, category: category, occurred_on: occurred_on,
           field_confidence: { "amount" => amount_confidence },
           overall_confidence: confidence, modality: modality)
    end

    def income(cents:, merchant: nil, confidence: 0.9)
      base(intent: "income", intent_confidence: confidence, amount_cents: cents,
           merchant: merchant, payment_method: "desconhecido",
           field_confidence: { "amount" => 0.95 }, overall_confidence: confidence)
    end

    def transfer(cents:, from: nil, to: nil, confidence: 0.95)
      base(intent: "transfer", intent_confidence: confidence, amount_cents: cents,
           payment_method: "desconhecido", instrument_phrase: from, to_instrument_phrase: to,
           field_confidence: { "amount" => 0.95 }, overall_confidence: confidence)
    end

    def installment(total_cents:, count:, merchant:, instrument: nil, method: "credito", confidence: 0.9)
      base(intent: "installment_purchase", intent_confidence: confidence,
           amount_cents: total_cents, installments_count: count, merchant: merchant,
           payment_method: method, instrument_phrase: instrument,
           field_confidence: { "amount" => 0.95 }, overall_confidence: confidence)
    end

    def query(kind, confidence: 0.9, instrument: nil)
      base(intent: "query", intent_confidence: confidence, query_kind: kind,
           instrument_phrase: instrument, payment_method: "desconhecido")
    end

    def edit_last(field_hint: nil, cents: nil, category: nil, confidence: 0.9)
      base(intent: "edit_last", intent_confidence: confidence, edit_field_hint: field_hint,
           amount_cents: cents, category: category, payment_method: "desconhecido",
           field_confidence: cents ? { "amount" => 0.95 } : {})
    end

    def undo(confidence: 0.9)
      base(intent: "undo_last", intent_confidence: confidence, payment_method: "desconhecido")
    end

    def base(**fields)
      cents = fields[:amount_cents]
      defaults = {
        amount_raw: cents ? format("%d,%02d", cents / 100, cents % 100) : nil,
        currency: "BRL", occurred_on: nil, instrument_phrase: nil,
        field_confidence: {}, overall_confidence: fields[:intent_confidence] || 0.9,
        modality: "text", source: "whatsapp_text", raw: {}
      }
      Whatsapp::Extraction.new(**defaults.merge(fields))
    end
  end
end
