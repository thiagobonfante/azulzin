module Whatsapp
  # Capture confidence: how much we trust the EXTRACTED AMOUNT enough to post it silently.
  # Under silent-auto-commit (Open Decision #5) the floor gates post-vs-park; the instrument
  # match separately decides assigned-vs-unassigned (a wrong account is never *posted* — an
  # unmatched instrument posts unassigned for in-app fix). So this score deliberately does
  # NOT fold in the match strength. See .plans/whats §4.7.
  class Confidence
    # Integer 0..100. Start HIGH (park more than you post) and lower it as the in-app
    # correction rate proves the extraction trustworthy. ENV override for ops; a settable
    # class attribute so it can be tuned (and stubbed in tests).
    DEFAULT_FLOOR = 80
    @floor = ENV.fetch("WHATSAPP_CONFIDENCE_FLOOR", DEFAULT_FLOOR).to_i
    class << self
      attr_accessor :floor
    end

    def initialize(extraction)
      @extraction = extraction
    end

    # LLMs are systematically overconfident, so self-report is a ceiling: take the min of the
    # amount field confidence and the overall confidence, then apply the modality factor
    # (text 1.0 > OCR 0.95 > ASR 0.90).
    def capture_score
      return installment_score unless @extraction.amount_present?
      amount_conf = (@extraction.field_confidence["amount"] || @extraction.overall_confidence).to_f
      base = [ amount_conf, @extraction.overall_confidence.to_f ].min
      # The overall ceiling exists because LLMs invent values; a VERBATIM amount can't be
      # invented. Terse "33 cartao" honestly reads low overall (no merchant, no date) while
      # the amount is string-certain — trust the amount field alone in that case.
      base = amount_conf if verbatim_amount?
      (base * @extraction.modality_factor * 100).round.clamp(0, 100)
    end

    def above_floor? = capture_score >= self.class.floor

    # A parcel-first installment ("10x de 349,90") legitimately carries its value in
    # installment_parcel_raw/total_raw with amount_raw null (the model never multiplies),
    # so there is no amount field to rate: score the overall confidence, trusting a
    # verbatim string the same way the amount path does.
    def installment_score
      return 0 unless @extraction.intent == "installment_purchase"
      raw = @extraction.installment_parcel_raw.presence || @extraction.installment_total_raw.presence
      return 0 if raw.blank?
      base = @extraction.overall_confidence.to_f
      base = 1.0 if verbatim?(raw)
      (base * @extraction.modality_factor * 100).round.clamp(0, 100)
    end

    def verbatim_amount? = verbatim?(@extraction.amount_raw.to_s)

    # `raw` appears digit-bounded in the message text ("33" never matches inside "133").
    def verbatim?(raw)
      text = @extraction.raw.is_a?(Hash) ? @extraction.raw["transcript"].to_s : ""
      raw.present? && text.match?(/(?<!\d)#{Regexp.escape(raw)}(?!\d)/)
    end
  end
end
