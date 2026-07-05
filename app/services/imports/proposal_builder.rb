require "digest"

# Turns one parsed document (§8 extraction) into D5 proposal objects and stamps the import's
# kind/institution/fingerprint, then flips it to `extracted`. Phase 1 builds bank_account
# proposals only (from formats that carry account identity — OFX; PDF extrato in Phase 2).
# Income/commitment classification lands in Phase 3. pids are deterministic/content-derived, so
# job retries and re-runs are idempotent (same input → same proposals, no duplicates).
module Imports
  module ProposalBuilder
    module_function

    def call(import)
      parsed = import.extraction || {}
      meta   = parsed["meta"] || {}
      institution = resolve_institution(meta)

      import.kind        = "bank_statement"
      import.institution = institution
      import.fingerprint = fingerprint(meta, institution)
      import.proposals   = build_proposals(parsed, meta, institution)
      import.status      = "extracted"
      import.save!
    end

    # COMPE code from the OFX BANKID (never the LLM). "0260" → "260"; "33" → "033". Fallback "000".
    def resolve_institution(meta)
      raw = meta.dig("acct", "bank_id")
      code = normalize_compe(raw)
      (code && Institution.find_by(code: code)) || Institution.find_by(code: Institution::OTHER_CODE)
    end

    def normalize_compe(raw)
      digits = Imports.digits(raw)
      return nil if digits.empty?

      digits.sub(/\A0+/, "").rjust(3, "0")
    end

    def fingerprint(meta, _institution)
      {
        "bank_code"             => meta.dig("acct", "bank_id"),
        "agency"                => meta.dig("acct", "branch_id"),
        "account_number"        => meta.dig("acct", "acct_id"),
        "period_start"          => meta["period_start"],
        "period_end"            => meta["period_end"],
        "ledger_balance_cents"  => meta["ledger_balance_cents"],
        "ledger_balance_as_of"  => meta["ledger_balance_as_of"]
      }.compact
    end

    def build_proposals(parsed, meta, institution)
      acct = meta["acct"] || {}
      return [] if acct["acct_id"].to_s.strip.empty? # no identity ⇒ no bank_account proposal

      [ bank_account_proposal(parsed, meta, institution) ]
    end

    def bank_account_proposal(_parsed, meta, institution)
      acct  = meta["acct"] || {}
      as_of = meta["ledger_balance_as_of"] || meta["period_end"]
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
          "balance_cents"    => meta["ledger_balance_cents"],
          "balance_as_of"    => as_of
        },
        "evidence" => [ {
          "kind"        => "bank_statement",
          "institution" => institution&.display_name,
          "date"        => as_of,
          "description" => account_line(acct),
          "amount_cents" => meta["ledger_balance_cents"]
        } ],
        "record" => nil
      }
    end

    def account_kind(acct_type)
      case acct_type.to_s.upcase
      when "SAVINGS" then "savings"
      else "checking"
      end
    end

    def account_line(acct)
      [ acct["branch_id"], acct["acct_id"] ].compact.join(" / ")
    end

    def pid(kind, identity)
      Digest::SHA1.hexdigest([ kind, *identity ].join("|"))[0, 12]
    end
  end
end
