require "test_helper"
require_relative "../../test_helpers/import_extraction_fixtures"

class Imports::DocumentExtractorTest < ActiveSupport::TestCase
  include ImportExtractionFixtures

  test "fatura: one card, titular last4, derived offset, Money.to_cents, year-inferred installment" do
    extraction = Imports::DocumentExtractor.call({ "pages" => [ "fatura text" ] }, client: FakeClient.new(FATURA_RESPONSE))
    card = extraction["meta"]["card"]

    assert_equal "card_bill", extraction["doc_kind"]
    assert_equal "8431", card["last4"] # titular = first non-virtual plastic
    assert_equal 13_259_000, card["credit_limit_cents"]
    assert_equal 2_170_636, card["current_bill_cents"]
    assert_equal 10, card["bill_due_day"]
    assert_equal 7, card["closing_offset_days"] # 10/07 − 03/07

    installment = extraction["rows"].find { it["installment"] }
    assert_equal "2025-11-15", installment["date"] # 15/11 inferred BACKWARD from 03/07/2026
    assert_equal 25_641, installment["amount_cents"]
    assert_equal 10, installment["installment"]["total"]
  end

  test "fatura: an FX purchase stays ONE row with fx folded, amount via Money.to_cents" do
    extraction = Imports::DocumentExtractor.call({ "pages" => [ "x" ] }, client: FakeClient.new(FATURA_RESPONSE))
    fx = extraction["rows"].find { it["fx"] }
    assert_equal 4_802_580, fx["amount_cents"]
    assert_equal "5,34", fx["fx"]["cotacao_raw"]
    assert_equal 2, extraction["rows"].size # not split into 3 lines
  end

  test "extrato: closing balance = the newest running Saldo, identity kept verbatim" do
    extraction = Imports::DocumentExtractor.call({ "pages" => [ "extrato" ] }, client: FakeClient.new(EXTRATO_RESPONSE))
    meta = extraction["meta"]
    assert_equal "bank_statement", extraction["doc_kind"]
    assert_equal 322_179, meta["closing_balance_cents"]
    assert_equal "01003172-6", meta["acct"]["acct_id"]
    assert_equal "033", meta["bank_code"]
    assert_equal "2026-06-30", meta["period_end"]
  end

  test "long documents page-batch: 1 metadata call + N row calls" do
    pages = Array.new(6) { "page text" }
    client = FakeClient.new(FATURA_RESPONSE, FATURA_RESPONSE)
    Imports::DocumentExtractor.call({ "pages" => pages }, client: client)
    assert_equal 1 + (6.0 / Imports::DocumentExtractor::PAGES_PER_BATCH).ceil, client.calls
  end

  test "call_vision sends image_url data-URLs and flags the extraction vision" do
    seen = nil
    client = Object.new
    client.define_singleton_method(:chat) { |messages:, schema:| seen = messages; FakeResult.new(FATURA_RESPONSE) }

    extraction = Imports::DocumentExtractor.call_vision([ "\x89PNGfakebytes" ], client: client)

    assert extraction["vision"]
    content = seen.last[:content]
    image_part = content.find { it["type"] == "image_url" }
    assert image_part.dig("image_url", "url").start_with?("data:image/png;base64,")
  end
end
