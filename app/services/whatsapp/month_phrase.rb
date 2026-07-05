module Whatsapp
  # Parses a natural month reference to a first-of-month Date (pay_commitment, v1.1 move_bill).
  # Deterministic — the LLM never picks the month. See 07 §3.
  module MonthPhrase
    module_function

    MONTHS = %w[janeiro fevereiro marco abril maio junho julho agosto setembro outubro novembro dezembro].freeze

    def parse(phrase, reference: Date.current)
      base = reference.beginning_of_month
      return base if phrase.blank?
      text = Whatsapp.normalize(phrase)
      return base >> 1 if text.match?(/proxim|que vem|seguinte/)
      return base << 1 if text.match?(/passad|anterior/)
      if (idx = MONTHS.index { |m| text.include?(m) })
        target = Date.new(reference.year, idx + 1, 1)
        target >= base ? target : (target >> 12)   # nearest current/future occurrence
      else
        base
      end
    end
  end
end
