require "digest"

# Turns one parsed document (§8/PDF extraction) into D5 proposal objects and stamps the import's
# kind/institution/fingerprint, then flips it to `extracted`. Handles bank_account (OFX + PDF
# extrato) and credit_card (PDF fatura). Income/commitment classification lands in Phase 3. pids
# are deterministic/content-derived, so job retries and re-runs are idempotent.
module Imports
  module ProposalBuilder
    module_function

    def call(import)
      parsed      = import.extraction || {}
      kind        = doc_kind(parsed)
      institution = resolve_institution(parsed)

      import.kind        = kind
      import.institution = institution
      import.fingerprint = fingerprint(parsed, kind, institution)
      import.proposals   = build_proposals(parsed, kind, institution)
      import.status      = "extracted"
      import.save!
    end

    # csv/ofx carry no doc_kind → they're always bank statements.
    def doc_kind(parsed)
      parsed["doc_kind"].presence || "bank_statement"
    end

    # Institution resolves in Ruby, never the LLM: printed COMPE first, else fuzzy name, else Outro.
    def resolve_institution(parsed)
      meta = parsed["meta"] || {}
      code = normalize_compe(meta.dig("acct", "bank_id") || meta["bank_code"])
      by_code = Institution.find_by(code: code) if code
      by_code || fuzzy_institution(meta["institution_name"]) || Institution.find_by(code: Institution::OTHER_CODE)
    end

    def normalize_compe(raw)
      digits = Imports.digits(raw)
      return nil if digits.empty?

      digits.sub(/\A0+/, "").rjust(3, "0")
    end

    # Generic banking words are NOT distinctive — "Banco Santander (Brasil)" must resolve to
    # Santander, not Banco do Brasil. Match on the longest distinctive institution-name token.
    GENERIC_TOKENS = %w[banco brasil brasileiro nacional financeira credito pagamentos digital].freeze

    def fuzzy_institution(name)
      return nil if name.blank?

      normalized = Imports.strip_accents(name.to_s.downcase)
      best, best_len = nil, 0
      Institution.where.not(code: Institution::OTHER_CODE).find_each do |institution|
        tokens = Imports.strip_accents(institution.name.downcase).split
                        .reject { |token| token.length < 4 || GENERIC_TOKENS.include?(token) }
        tokens.each do |token|
          next unless normalized.include?(token) && token.length > best_len

          best, best_len = institution, token.length
        end
      end
      best
    end

    def fingerprint(parsed, kind, _institution)
      meta = parsed["meta"] || {}
      base =
        if kind == "card_bill"
          card = meta["card"] || {}
          { "last4" => card["last4"], "holder_hint" => meta["holder_name"],
            "credit_limit_cents" => card["credit_limit_cents"], "current_bill_cents" => card["current_bill_cents"] }
        else
          acct = meta["acct"] || {}
          { "bank_code" => acct["bank_id"] || meta["bank_code"], "agency" => acct["branch_id"],
            "account_number" => acct["acct_id"],
            "ledger_balance_cents" => balance_cents(meta), "ledger_balance_as_of" => balance_as_of(meta) }
        end
      base.merge("period_start" => meta["period_start"], "period_end" => meta["period_end"]).compact
    end

    def build_proposals(parsed, kind, institution)
      meta = parsed["meta"] || {}
      if kind == "card_bill"
        return [] if meta.dig("card", "last4").to_s.strip.empty?

        [ credit_card_proposal(meta, institution) ]
      else
        return [] if meta.dig("acct", "acct_id").to_s.strip.empty?

        [ bank_account_proposal(meta, institution) ]
      end
    end

    def bank_account_proposal(meta, institution)
      acct  = meta["acct"] || {}
      as_of = balance_as_of(meta)
      identity = [ institution&.code, Imports.digits(acct["branch_id"]), Imports.normalize_account(acct["acct_id"]) ]
      {
        "pid"        => pid("bank_account", identity),
        "kind"       => "bank_account",
        "state"      => "proposed",
        "confidence" => 0.9,
        "payload" => {
          "institution_code" => institution&.code,
          "kind"             => account_kind(acct["acct_type"]),
          "nickname"         => nil,
          "agency"           => acct["branch_id"],
          "account_number"   => acct["acct_id"],
          "balance_cents"    => balance_cents(meta),
          "balance_as_of"    => as_of
        },
        "evidence" => [ evidence("bank_statement", institution, as_of, account_line(acct), balance_cents(meta)) ],
        "record" => nil
      }
    end

    def credit_card_proposal(meta, institution)
      card = meta["card"] || {}
      identity = [ institution&.code, Imports.digits(card["last4"]) ]
      {
        "pid"        => pid("credit_card", identity),
        "kind"       => "credit_card",
        "state"      => "proposed",
        "confidence" => card["bill_due_day"] ? 0.9 : 0.6,
        "payload" => {
          "institution_code"    => institution&.code,
          "last4"               => card["last4"],
          "nickname"            => nil,
          "bill_due_day"        => card["bill_due_day"],
          "closing_offset_days" => card["closing_offset_days"],
          "credit_limit_cents"  => card["credit_limit_cents"],
          "current_bill_cents"  => card["current_bill_cents"]
        },
        "evidence" => [ evidence("card_bill", institution, meta["period_end"],
                                 card["last4"] && "final #{card["last4"]}", card["current_bill_cents"]) ],
        "record" => nil
      }
    end

    def balance_cents(meta) = meta["ledger_balance_cents"] || meta["closing_balance_cents"]
    def balance_as_of(meta) = meta["ledger_balance_as_of"] || meta["period_end"]

    def account_kind(acct_type)
      acct_type.to_s.upcase == "SAVINGS" ? "savings" : "checking"
    end

    def account_line(acct)
      [ acct["branch_id"], acct["acct_id"] ].compact_blank.join(" / ").presence
    end

    def evidence(kind, institution, date, description, amount_cents)
      { "kind" => kind, "institution" => institution&.display_name, "date" => date,
        "description" => description, "amount_cents" => amount_cents }
    end

    def pid(kind, identity)
      Digest::SHA1.hexdigest([ kind, *identity ].join("|"))[0, 12]
    end
  end
end
