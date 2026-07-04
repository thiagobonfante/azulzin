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
      return 0 unless @extraction.amount_present?
      amount_conf = @extraction.field_confidence["amount"] || @extraction.overall_confidence
      base = [ amount_conf.to_f, @extraction.overall_confidence.to_f ].min
      (base * @extraction.modality_factor * 100).round.clamp(0, 100)
    end

    def above_floor? = capture_score >= self.class.floor
  end
end
