require "test_helper"

class Whatsapp::MatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @nubank_card = CreditCard.create!(user: @user, institution: Institution.find_by(code: "260"))
    @itau_account = BankAccount.create!(user: @user, institution: Institution.find_by(code: "341"))
  end

  def match(phrase:, method: "desconhecido")
    Whatsapp::Matcher.new(@user, Whatsapp::Extraction.new(instrument_phrase: phrase, payment_method: method)).call
  end

  test "resolves a card by its brand alias" do
    r = match(phrase: "no cartão Nubank", method: "credito")
    assert_equal @nubank_card, r.instrument
    assert_equal 1.0, r.c_match
  end

  test "KIND keyword routes débito to the bank account" do
    r = match(phrase: "na conta do Itaú", method: "debito")
    assert_equal @itau_account, r.instrument
  end

  test "no phrase → instrument_missing" do
    r = match(phrase: nil)
    assert_nil r.instrument
    assert_equal "instrument_missing", r.reason
  end

  test "brand the user doesn't have → no_such_instrument" do
    r = match(phrase: "no Bradesco", method: "credito")
    assert_nil r.instrument
    assert_equal "no_such_instrument", r.reason
  end

  test "two cards at the same bank → needs_disambiguation" do
    CreditCard.create!(user: @user, institution: Institution.find_by(code: "260"), nickname: "Ultravioleta")
    r = match(phrase: "cartão Nubank", method: "credito")
    assert_nil r.instrument
    assert_equal "needs_disambiguation", r.reason
    assert_operator r.candidates.size, :>=, 2
  end

  test "short brand aliases never match fuzzily (whole token only)" do
    # "bb" (Banco do Brasil) must not fuzzy-match an unrelated word.
    BankAccount.create!(user: @user, institution: Institution.find_by(code: "001"))
    r = match(phrase: "no boteco", method: "debito")
    assert_not_equal "001", r.instrument&.institution&.code
  end
end
