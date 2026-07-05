require "digest"

# Turns one parsed document into D5 proposal objects and stamps the import's kind/institution/
# fingerprint, then flips it to `extracted`. Instruments (bank_account/credit_card) come from the
# metadata; income/commitment proposals come from the rows via deterministic signals + the
# recurring classifier. Recurring proposals are built ONLY when the import produced an instrument
# to attach them to — so the CSV twin (no account header) never double-builds the OFX's rows, and
# every dependent has a same-import instrument to resolve. pids are content-derived → idempotent.
module Imports
  module ProposalBuilder
    module_function

    FIXED_BILL_SIGNALS = %w[debito_automatico pix_automatico mensalidade prestacao boleto].freeze
    NAME_LIMIT = 80

    def call(import, client: nil)
      parsed      = import.extraction || {}
      kind        = doc_kind(parsed)
      institution = resolve_institution(parsed)

      import.kind        = kind
      import.institution = institution
      import.fingerprint = fingerprint(parsed, kind, institution)

      instruments = build_instrument_proposals(parsed, kind, institution)
      recurring   = build_recurring_proposals(parsed, kind, institution, instruments.first, client)
      import.proposals = instruments + recurring
      import.status = "extracted"
      import.save!
    end

    def doc_kind(parsed)
      parsed["doc_kind"].presence || "bank_statement"
    end

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

    # ── instruments ───────────────────────────────────────────────────────────
    def build_instrument_proposals(parsed, kind, institution)
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
          "institution_code" => institution&.code, "kind" => account_kind(acct["acct_type"]),
          "nickname" => nil, "agency" => acct["branch_id"], "account_number" => acct["acct_id"],
          "balance_cents" => balance_cents(meta), "balance_as_of" => as_of
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
          "institution_code" => institution&.code, "last4" => card["last4"], "nickname" => nil,
          "bill_due_day" => card["bill_due_day"], "closing_offset_days" => card["closing_offset_days"],
          "credit_limit_cents" => card["credit_limit_cents"], "current_bill_cents" => card["current_bill_cents"]
        },
        "evidence" => [ evidence("card_bill", institution, meta["period_end"],
                                 card["last4"] && "final #{card["last4"]}", card["current_bill_cents"]) ],
        "record" => nil
      }
    end

    # ── income / commitments (Phase 3) ──────────────────────────────────────────
    def build_recurring_proposals(parsed, kind, institution, instrument, client)
      return [] if instrument.nil? # dependents need a same-import instrument to attach to

      rows = SignalTagger.tag(Array(parsed["rows"]))
      candidates = rows.reject { |row| SignalTagger.excluded?(row) }
      return [] if candidates.empty?

      classified = RecurringClassifier.call(candidates, client: client).index_by { it["id"] }
      period_end = parse_date(parsed.dig("meta", "period_end"))
      proposals = candidates.each_with_index.filter_map do |row, id|
        recurring_proposal(row, classified[id] || {}, instrument, kind, institution, period_end)
      end
      merge_by_pid(proposals)
    end

    def recurring_proposal(row, classification, instrument, doc_kind, institution, period_end)
      label = effective_label(row, classification)
      return nil if %w[one_off noise transfer].include?(label)
      return nil if label == "income" && row["direction"] != "in"
      return nil if %w[fixed_bill subscription installment].include?(label) && row["direction"] != "out"

      conf = Confidence.effective(row, classification["confidence"], label: label, single_month: label == "income")
      ref  = { "pid" => instrument["pid"] }
      case label
      when "income"       then income_proposal(row, classification, ref, conf, doc_kind, institution)
      when "installment"  then installment_proposal(row, classification, ref, conf, instrument, doc_kind, institution, period_end)
      else                     commitment_proposal(row, classification, ref, conf, label, doc_kind, institution)
      end
    end

    # Deterministic signals force the label; the LLM only fills the gaps (never overridden down).
    def effective_label(row, classification)
      signals = Array(row["signals"])
      return "installment"  if signals.include?("installment_counter") || row["installment"]
      return "subscription" if signals.include?("known_subscription")
      return "fixed_bill"   if (signals & FIXED_BILL_SIGNALS).any?

      classification["label"].presence || "one_off"
    end

    def income_proposal(row, classification, ref, conf, doc_kind, institution)
      name = clip(classification["commitment_name"] || classification["merchant_canonical"] || row["description"])
      {
        "pid"        => pid("income", [ ref["pid"], classification["merchant_canonical"] || name ]),
        "kind"       => "income",
        "state"      => "proposed",
        "confidence" => conf,
        "payload" => {
          "name" => name, "amount_cents" => row["amount_cents"], "schedule_kind" => "fixed_day",
          "schedule_day" => (classification["schedule_day"] || day_of(row["date"]) || 1), "instrument_ref" => ref
        },
        "evidence" => [ evidence(doc_kind, institution, row["date"], row["description"], row["amount_cents"]) ],
        "record" => nil
      }
    end

    def commitment_proposal(row, classification, ref, conf, label, doc_kind, institution)
      commitment_kind = label == "subscription" ? "subscription" : "fixed"
      name = clip(classification["commitment_name"] || classification["merchant_canonical"] || row["description"])
      schedule_day = commitment_kind == "fixed" ? (classification["schedule_day"] || day_of(row["date"]) || 1) : classification["schedule_day"]
      {
        "pid"        => pid("commitment", [ commitment_kind, classification["merchant_canonical"] || name, row["amount_cents"] ]),
        "kind"       => "commitment",
        "state"      => "proposed",
        "confidence" => conf,
        "payload" => {
          "commitment_kind" => commitment_kind, "name" => name, "amount_cents" => row["amount_cents"],
          "schedule_kind" => "fixed_day", "schedule_day" => schedule_day,
          "starts_on" => row["date"], "instrument_ref" => ref
        },
        "evidence" => [ evidence(doc_kind, institution, row["date"], row["description"], row["amount_cents"]) ],
        "record" => nil
      }
    end

    def installment_proposal(row, classification, ref, conf, instrument, doc_kind, institution, period_end)
      current, total = installment_counter(row)
      return commitment_proposal(row, classification, ref, conf, "fixed_bill", doc_kind, institution) if total.to_i < 1

      name   = clip(classification["commitment_name"] || classification["merchant_canonical"] || row["description"])
      parcel = row["amount_cents"]
      card   = instrument["kind"] == "credit_card"
      anchor = card ? period_end : parse_date(row["date"])
      starts = installment_start(anchor, current)
      {
        "pid"        => pid("commitment", [ "installment", classification["merchant_canonical"] || name, parcel, total ]),
        "kind"       => "commitment",
        "state"      => "proposed",
        "confidence" => conf,
        "payload" => {
          "commitment_kind" => "installment", "name" => name, "amount_cents" => parcel,
          "installments_count" => total, "total_cents" => parcel * total, "schedule_kind" => "fixed_day",
          "schedule_day" => (card ? nil : day_of(row["date"])), "starts_on" => starts&.iso8601, "instrument_ref" => ref
        },
        "evidence" => [ evidence(doc_kind, institution, row["date"], row["description"], parcel, installment: [ current, total ]) ],
        "record" => nil
      }
    end

    def installment_counter(row)
      return [ row.dig("installment", "current"), row.dig("installment", "total") ] if row["installment"]

      SignalTagger.installment_counter(row["description"]) || [ nil, nil ]
    end

    # starts_on = the parcel-1 occurrence month, walked back from the observed occurrence (§3.6).
    def installment_start(anchor, current)
      return nil unless anchor && current

      anchor << (current - 1)
    end

    def merge_by_pid(proposals)
      proposals.group_by { it["pid"] }.map do |_pid, group|
        next group.first if group.size == 1

        group.first.merge(
          "evidence"   => group.flat_map { it["evidence"] },
          "confidence" => group.map { it["confidence"] }.max
        )
      end
    end

    # ── shared ─────────────────────────────────────────────────────────────────
    def balance_cents(meta) = meta["ledger_balance_cents"] || meta["closing_balance_cents"]
    def balance_as_of(meta) = meta["ledger_balance_as_of"] || meta["period_end"]

    def account_kind(acct_type)
      acct_type.to_s.upcase == "SAVINGS" ? "savings" : "checking"
    end

    def account_line(acct)
      [ acct["branch_id"], acct["acct_id"] ].compact_blank.join(" / ").presence
    end

    def evidence(kind, institution, date, description, amount_cents, installment: nil)
      { "kind" => kind, "institution" => institution&.display_name, "date" => date,
        "description" => description, "amount_cents" => amount_cents, "installment" => installment }.compact
    end

    def clip(name) = name.to_s.strip[0, NAME_LIMIT].presence || "—"

    def day_of(iso)
      Date.iso8601(iso.to_s).day
    rescue ArgumentError, Date::Error
      nil
    end

    def parse_date(iso)
      Date.iso8601(iso.to_s)
    rescue ArgumentError, Date::Error
      nil
    end

    def pid(kind, identity)
      Digest::SHA1.hexdigest([ kind, *identity ].join("|"))[0, 12]
    end
  end
end
