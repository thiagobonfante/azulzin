module Whatsapp
  # Parses a goal's target-month WORDS into a first-of-month Date, or nil (→ re-ask).
  # Deliberately NOT MonthPhrase: its /que vem/ branch fires before month names, so
  # "outubro do ano que vem" would come back as next month, it has no future-year concept,
  # and it defaults blank to the current month — all wrong for a goal date. Deterministic;
  # the LLM only ever emits the raw words. (Round 3 P6, decision 8.)
  module GoalMonthPhrase
    module_function

    MONTHS = MonthPhrase::MONTHS
    NEXT_YEAR_RE = /ano que vem|proximo ano|ano seguinte/

    # → first-of-month Date within (current month, reference + 10 years], else nil.
    def parse(phrase, reference: Date.current)
      return nil if phrase.blank?
      clamp(candidate(Whatsapp.normalize(phrase), reference), reference)
    end

    def candidate(text, reference)
      idx  = MONTHS.index { |m| text.include?(m) }
      year = text[/\b(20\d\d)\b/, 1]&.to_i
      if idx
        return Date.new(year, idx + 1, 1) if year
        return Date.new(reference.year + 1, idx + 1, 1) if text.match?(NEXT_YEAR_RE)
        nearest_future(idx, reference)
      elsif (n = text[/\b(\d{1,3}) mes(es)?\b/, 1]&.to_i)
        reference.beginning_of_month >> n    # "em 6 meses"
      end
      # bare "ano que vem" (no month) falls through to nil — re-asking beats guessing a month
    end

    # Bare month name: this year if still ahead, else next year (the clamp excludes the
    # current month, so the current month's own name lands a year out).
    def nearest_future(idx, reference)
      target = Date.new(reference.year, idx + 1, 1)
      target > reference.beginning_of_month ? target : (target >> 12)
    end

    def clamp(date, reference)
      return nil if date.nil?
      return nil if date <= reference.beginning_of_month
      return nil if date > reference.beginning_of_month >> 120
      date
    end
  end
end
