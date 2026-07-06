require "test_helper"

class Imports::SignalTaggerTest < ActiveSupport::TestCase
  test "tags each deterministic signal from the sample descriptions" do
    { "debito_automatico"   => "DEBITO AUT. COPEL",
      "pix_automatico"      => "PIX AUTOMATICO ENVIADO TOKIO MARINE",
      "mensalidade"         => "MENSALIDADE DE SEGURO",
      "prestacao"           => "OPERACOES CREDITO IMOBILIARIO PREST CR IM",
      "installment_counter" => "MENSALIDADE DE SEGURO Parc 027/036 INCENDIO RES",
      "known_subscription"  => "NETFLIX.COM SAO PAULO",
      "sweep_interest"      => "REMUNERACAO APLICACAO AUTOMATICA",
      "fx_subline"          => "IOF SOBRE COMPRA INTERNACIONAL",
      "card_bill_payment"   => "DEBITO AUT. FATURA CARTAO VISA FINAL 8431" }.each do |signal, description|
      assert_includes Imports::SignalTagger.signals_for(description), signal, description
    end
  end

  test "installment_counter matches both Parc NN/MM and Parcela NN/MM" do
    assert_equal [ 27, 36 ], Imports::SignalTagger.installment_counter("Parc 027/036 INCENDIO")
    assert_equal [ 8, 10 ],  Imports::SignalTagger.installment_counter("BRITANIA Parcela 08/10")
    assert_nil Imports::SignalTagger.installment_counter("no counter here")
  end

  test "excluded? flags sweep/fx/card_bill_payment but not fixed-bill signals" do
    assert Imports::SignalTagger.excluded?("signals" => [ "sweep_interest" ])
    assert Imports::SignalTagger.excluded?("signals" => [ "card_bill_payment", "debito_automatico" ])
    assert_not Imports::SignalTagger.excluded?("signals" => [ "debito_automatico" ])
  end

  test "card_bill_last4 captures the linked plastic" do
    assert_equal "8431", Imports::SignalTagger.card_bill_last4("FATURA CARTAO VISA FINAL 8431")
  end
end
