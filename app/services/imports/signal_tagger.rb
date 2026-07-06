# Deterministic pre-tagging (D4, §6): frozen regexes over the normalized description, run in Ruby
# BEFORE the classifier. Signal rows carry a 0.9 confidence floor (the regex IS the evidence);
# exclusion signals short-circuit — those rows never reach the LLM and never become proposals.
module Imports
  module SignalTagger
    module_function

    EXCLUDED = %w[sweep_interest fx_subline card_bill_payment].freeze

    # Known-subscription merchants (normalized, accent-stripped). Extending is a one-line diff.
    KNOWN_SUBSCRIPTIONS = %w[NETFLIX SPOTIFY GOOGLE\ ONE DL*GOOGLE APPLE.COM APPLE\ COM
                             OPENAI CHATGPT AMAZON\ PRIME PRIME\ VIDEO ESFERA IFOOD\ CLUBE
                             DISNEY HBO MAX YOUTUBE\ PREMIUM].freeze

    RULES = {
      "installment_counter" => /\bPARC(?:ELA)?\.?\s*\d{1,3}\s*\/\s*\d{1,3}\b/,
      "debito_automatico"   => /\bDEBITO\s+AUT/,
      "pix_automatico"      => /\bPIX\s+AUTOMATICO\b/,
      "mensalidade"         => /\bMENSALIDADE\b/,
      "prestacao"           => /\bPREST(?:ACAO)?\b|\bCONSORCIO\b|\bCR\s*IM\b/,
      "boleto"              => /\bPAGAMENTO\s+DE\s+BOLETO\b/,
      "sweep_interest"      => /\bREMUNERACAO\s+APLICACAO\b/,
      "fx_subline"          => /\bIOF\b|\bCOTACAO\b|\bVARIACAO\s+CAMBIAL\b/,
      "card_bill_payment"   => %r{PAGAMENTO\s+DE\s+FATURA|DEB\s+AUTOM\s+DE\s+FATURA|FATURA\s+CARTAO.*FINAL\s+\d{4}}
    }.freeze

    def tag(rows)
      rows.map { |row| row.merge("signals" => (Array(row["signals"]) | signals_for(row["description"])).uniq) }
    end

    def signals_for(description)
      up = Imports.strip_accents(description.to_s.upcase)
      signals = RULES.filter_map { |name, regex| name if up.match?(regex) }
      signals << "known_subscription" if KNOWN_SUBSCRIPTIONS.any? { |merchant| up.include?(merchant) }
      signals
    end

    def excluded?(row) = (Array(row["signals"]) & EXCLUDED).any?

    # current/total from a "Parcela NN/MM" / "Parc NN/MM" row, else nil.
    def installment_counter(description)
      m = Imports.strip_accents(description.to_s.upcase).match(/\bPARC(?:ELA)?\.?\s*(\d{1,3})\s*\/\s*(\d{1,3})\b/)
      m && [ m[1].to_i, m[2].to_i ]
    end

    # last4 captured from a "FATURA CARTAO ... FINAL 8431" row (the card↔extrato link, §9.4).
    def card_bill_last4(description)
      Imports.strip_accents(description.to_s.upcase)[/FINAL\s+(\d{4})/, 1]
    end
  end
end
