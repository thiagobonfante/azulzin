# Confidence math (D4, §7): min(LLM self-report, all applicable caps), then raise to the signal
# floor ONLY when no cap fired (a deterministic signal IS the evidence). Mirrors
# ReceiptExtractor.effective_confidence. The 0.8 review floor (pre-check threshold) is applied in
# the view, not here.
module Imports
  module Confidence
    module_function

    REVIEW_FLOOR = 0.8
    SIGNAL_FLOOR = 0.9
    VISION_CAP   = 0.75 # OCR-grade reads always land in "Para revisar"
    DETERMINISTIC = %w[installment_counter debito_automatico pix_automatico mensalidade
                       prestacao boleto known_subscription].freeze

    def effective(row, llm_confidence, label:, single_month: false, vision: false)
      base = (llm_confidence || 0.5).to_f
      caps = []
      caps << 0.5  if row["amount_cents"].to_i <= 0           # can't create money from a guessed amount
      caps << 0.6  if row["date"].blank?                      # schedule guesses come from the date
      caps << 0.7  if label == "income" && single_month       # one credit isn't a pattern — never pre-checked
      caps << 0.75 if vision                                  # OCR-grade reads always land in "Para revisar"

      return [ base, caps.min ].min if caps.any?              # a cap fired → no floor
      deterministic?(row) ? [ base, SIGNAL_FLOOR ].max : base
    end

    def deterministic?(row) = (Array(row["signals"]) & DETERMINISTIC).any?
  end
end
