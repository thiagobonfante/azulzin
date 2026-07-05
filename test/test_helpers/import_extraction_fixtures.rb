# Canned LLM responses + a fake OpenRouter client (DI, no VCR — D10) for the document-import
# extraction tests. The anonymized synthetic Santander fatura/extrato — the real samples in
# .plans/auto/ carry live PII and are never committed.
module ImportExtractionFixtures
  FakeResult = Struct.new(:parsed)

  # Returns the given responses in call order, repeating the last (metadata call then row calls).
  class FakeClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = 0
    end

    def chat(**)
      @calls += 1
      FakeResult.new(@responses[[ @calls - 1, @responses.size - 1 ].min])
    end
  end

  FATURA_RESPONSE = {
    "doc_kind" => "card_bill",
    "institution_name" => "Banco Santander (Brasil) S.A.",
    "bank_code" => nil, "agency" => nil, "account_number" => nil,
    "holder_name" => "THIAGO EXEMPLO",
    "period_start_raw" => "03/06/2026", "period_end_raw" => "03/07/2026",
    "closing_balance_raw" => nil,
    "card" => {
      "sections" => [
        { "last4" => "8431", "holder" => "THIAGO EXEMPLO", "is_virtual" => false },
        { "last4" => "6463", "holder" => "VITORIA",        "is_virtual" => false },
        { "last4" => "5454", "holder" => "@THIAGO",        "is_virtual" => true }
      ],
      "limit_raw" => "132.590,00", "total_raw" => "21.706,36",
      "due_date_raw" => "10/07/2026", "melhor_dia_raw" => "04/08"
    },
    "rows" => [
      { "date_raw" => "15/11", "description" => "BRITANIA", "amount_raw" => "256,41", "direction" => "debit",
        "installment" => { "current" => 8, "total" => 10 }, "fx" => nil, "section_last4" => "8431" },
      { "date_raw" => "20/06", "description" => "COMPRA EUA", "amount_raw" => "48.025,80", "direction" => "debit",
        "installment" => nil,
        "fx" => { "usd_raw" => "9,00", "cotacao_raw" => "5,34", "iof_raw" => "1,50" }, "section_last4" => "8431" }
    ],
    "overall_confidence" => 0.9
  }.freeze

  EXTRATO_RESPONSE = {
    "doc_kind" => "bank_statement",
    "institution_name" => "Banco Santander (Brasil) S.A.",
    "bank_code" => "033", "agency" => "1616", "account_number" => "01003172-6",
    "holder_name" => "THIAGO", "period_start_raw" => "01/06/2026", "period_end_raw" => "30/06/2026",
    "closing_balance_raw" => "3.221,79", "card" => nil,
    "rows" => [
      { "date_raw" => "22/06", "description" => "PREST CR IM", "amount_raw" => "5.012,16", "direction" => "debit",
        "installment" => nil, "fx" => nil, "section_last4" => nil }
    ],
    "overall_confidence" => 0.9
  }.freeze

  def fatura_extraction  = Imports::DocumentExtractor.build(FATURA_RESPONSE)
  def extrato_extraction = Imports::DocumentExtractor.build(EXTRATO_RESPONSE)

  # Stub the recurring-classifier LLM call (DI). `response` is the row-label array it returns; the
  # default [] means non-signal rows fall to one_off (deterministic-signal rows still classify in
  # Ruby). Wrap any ProposalBuilder.call / job.perform that processes rows.
  def stub_classifier(response = [])
    Imports::RecurringClassifier.stub(:call, ->(_rows, **_kwargs) { response }) { yield }
  end
end
