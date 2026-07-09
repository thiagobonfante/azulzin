require "test_helper"

# Deterministic goal-date parsing (round 3 P6). NOT MonthPhrase: its /que vem/ branch fires
# before month names ("outubro do ano que vem" → next month) — the regression pinned here.
class Whatsapp::GoalMonthPhraseTest < ActiveSupport::TestCase
  REF = Date.new(2026, 7, 15)

  CASES = {
    # month + next-year words → that month NEXT year (the MonthPhrase bug this parser exists for)
    "outubro do ano que vem"  => Date.new(2027, 10, 1),
    "março do próximo ano"    => Date.new(2027, 3, 1),
    # bare month → nearest future occurrence
    "outubro"                 => Date.new(2026, 10, 1),
    "março"                   => Date.new(2027, 3, 1),   # already passed this year
    "julho"                   => Date.new(2027, 7, 1),   # current month → a year out
    # explicit year honored
    "outubro de 2027"         => Date.new(2027, 10, 1),
    "dezembro 2027"           => Date.new(2027, 12, 1),
    # relative months
    "em 6 meses"              => Date.new(2027, 1, 1),
    "em 18 meses"             => Date.new(2028, 1, 1),
    "em 1 mês"                => Date.new(2026, 8, 1),
    # nil: too vague, past, out of range, or noise
    "ano que vem"             => nil,                    # no month — re-ask beats guessing
    "outubro de 2020"         => nil,                    # past
    "julho de 2026"           => nil,                    # current month excluded
    "agosto de 2036"          => nil,                    # > reference + 10 years
    "em 200 meses"            => nil,
    "sei lá"                  => nil,
    ""                        => nil
  }.freeze

  test "table: phrase → first-of-month date (reference 2026-07-15)" do
    CASES.each do |phrase, expected|
      actual = Whatsapp::GoalMonthPhrase.parse(phrase, reference: REF)
      if expected.nil?
        assert_nil actual, "phrase: #{phrase.inspect}"
      else
        assert_equal expected, actual, "phrase: #{phrase.inspect}"
      end
    end
  end

  test "nil phrase and accents/case are handled" do
    assert_nil Whatsapp::GoalMonthPhrase.parse(nil, reference: REF)
    assert_equal Date.new(2027, 3, 1), Whatsapp::GoalMonthPhrase.parse("MARÇO do ANO QUE VEM", reference: REF)
  end
end
