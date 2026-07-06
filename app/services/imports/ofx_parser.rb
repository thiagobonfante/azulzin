require "bigdecimal"

# Hand-rolled, SGML-tolerant OFX 1.x reader (§7.2). NOT an XML parser: OFX 1.x leaf tags may or
# may not have closing tags. A line-oriented tag scan routes each leaf to the innermost open
# aggregate, so closed-tag and unclosed-leaf files parse identically. TRNAMT/BALAMT are spec-fixed
# dot-decimal → BigDecimal (never Money.to_cents, whose pt-BR heuristic could misread "1.234").
module Imports
  module OfxParser
    module_function

    AGGREGATES = %w[STMTRS CCSTMTRS BANKACCTFROM CCACCTFROM BANKTRANLIST STMTTRN
                    LEDGERBAL AVAILBAL BALLIST BAL].freeze
    TAG = /<(\/?[A-Za-z0-9._]+)>([^<\r\n]*)/

    def call(bytes)
      body = Imports.decode(bytes).split(/<OFX>/i, 2).last.to_s
      state = { context: [], cur: nil, txns: [], acct: {}, tranlist: {}, ledger: {} }

      body.scan(TAG) do |raw_tag, value|
        tag = raw_tag.upcase
        value = value.strip
        if raw_tag.start_with?("/")
          close(tag[1..], state)
        elsif AGGREGATES.include?(tag)
          open_aggregate(tag, state)
        else
          assign_leaf(tag, value, state)
        end
      end
      state[:txns] << state[:cur] if state[:cur]

      build_result(state)
    end

    def open_aggregate(tag, state)
      if tag == "STMTTRN"
        state[:txns] << state[:cur] if state[:cur] # flush an unclosed previous txn
        state[:cur] = {}
      end
      state[:context].push(tag)
    end

    def close(name, state)
      if name == "STMTTRN"
        state[:txns] << state[:cur] if state[:cur]
        state[:cur] = nil
      end
      state[:context].pop if state[:context].last == name
    end

    def assign_leaf(tag, value, state)
      state[:acct]["currency"] = value if tag == "CURDEF"

      case state[:context].last
      when "STMTTRN"
        assign_txn(tag, value, state[:cur])
      when "BANKACCTFROM", "CCACCTFROM"
        assign_acct(tag, value, state[:acct])
      when "BANKTRANLIST"
        state[:tranlist]["start"] = value if tag == "DTSTART"
        state[:tranlist]["end"]   = value if tag == "DTEND"
      when "LEDGERBAL" # NOT while inside BALLIST/BAL — that's a different context frame
        state[:ledger]["amount"] = value if tag == "BALAMT"
        state[:ledger]["as_of"]  = value if tag == "DTASOF"
      end
    end

    def assign_txn(tag, value, cur)
      return if cur.nil?

      case tag
      when "FITID"    then cur["external_id"] = value
      when "DTPOSTED" then cur["date"] = value
      when "TRNAMT"   then cur["amount"] = value
      when "TRNTYPE"  then cur["trntype"] = value
      when "MEMO", "NAME" then cur["description"] = [ cur["description"], value ].compact.join(" ").strip
      end
    end

    def assign_acct(tag, value, acct)
      case tag
      when "BANKID"   then acct["bank_id"] = value
      when "BRANCHID" then acct["branch_id"] = value
      when "ACCTID"   then acct["acct_id"] = value
      when "ACCTTYPE" then acct["acct_type"] = value
      end
    end

    def build_result(state)
      meta = {
        "acct" => state[:acct].slice("bank_id", "branch_id", "acct_id", "acct_type"),
        "currency" => state[:acct]["currency"],
        "period_start" => ofx_date(state[:tranlist]["start"])&.iso8601,
        "period_end"   => ofx_date(state[:tranlist]["end"])&.iso8601,
        "ledger_balance_cents"  => amount_cents(state[:ledger]["amount"]),
        "ledger_balance_as_of"  => ofx_date(state[:ledger]["as_of"])&.iso8601
      }
      { "format" => "ofx", "meta" => meta, "rows" => state[:txns].map { |t| normalize_txn(t) } }
    end

    def normalize_txn(txn)
      cents = amount_cents(txn["amount"]) || 0
      date  = ofx_date(txn["date"])
      {
        "date"         => date&.iso8601,
        "description"  => txn["description"].to_s.gsub(/\s+/, " ").strip,
        "amount_cents" => cents.abs,
        "direction"    => cents.negative? ? "out" : "in",
        "external_id"  => txn["external_id"].presence,
        "raw"          => txn,
        "signals"      => date ? [] : [ "date_unparsed" ]
      }
    end

    # OFX amounts are spec-fixed dot-decimal: BigDecimal, never Money.to_cents.
    def amount_cents(value)
      v = value.to_s.strip
      v.empty? ? nil : (BigDecimal(v) * 100).to_i
    rescue ArgumentError
      nil
    end

    def ofx_date(value)
      v = value.to_s.strip.sub(/\[[^\]]*\]\z/, "")
      return nil if v.length < 8

      Date.strptime(v[0, 8], "%Y%m%d")
    rescue ArgumentError
      nil
    end
  end
end
