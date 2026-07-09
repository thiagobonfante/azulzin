module Whatsapp
  # The normalized result of extracting a transaction from a message (text, transcript, or
  # receipt). amount_cents is computed in RUBY from amount_raw (the LLM never does the
  # arithmetic — Review P1-2). Consumed by Matcher → Confidence → Decider (expense) or by the
  # per-intent handlers (Interpreter). Intent + intent-specific fields added in 07 (R9).
  Extraction = Struct.new(
    :amount_raw, :amount_cents, :currency, :merchant, :occurred_on, :payment_method,
    :instrument_phrase, :field_confidence, :overall_confidence, :modality, :source, :raw,
    # --- intent layer (07 §3) ---
    :intent, :intent_confidence, :to_instrument_phrase, :installments_count,
    :installment_total_raw, :installment_parcel_raw, :commitment_phrase, :target_bill_raw,
    :edit_field_hint, :query_kind, :category,
    # --- create_goal (round 3 P6) — raw words only; cents/dates computed in Ruby ---
    :goal_kind, :goal_name, :goal_month_phrase, :goal_initial_saved_raw,
    keyword_init: true
  ) do
    def amount_present?     = amount_cents.present? && amount_cents != 0
    def instrument_named?   = instrument_phrase.present?
    def field_confidence    = self[:field_confidence] || {}
    def overall_confidence  = self[:overall_confidence] || 0.0

    # Defaults so pre-intent-layer extractions (and receipts) behave as plain expenses.
    def intent            = self[:intent].presence || "expense"
    def intent_confidence = self[:intent_confidence] || 0.0

    # Modality reliability ceiling (text most reliable, ASR least). See .plans/whats §4.7.
    def modality_factor
      case modality.to_s
      when "audio" then 0.90
      when "image" then 0.95
      else 1.00
      end
    end
  end
end
