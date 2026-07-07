# The commit point (D7): accepted proposal pids become real BankAccounts/CreditCards/Incomes/
# Commitments — the same records the wizard's manual forms create. Two global passes (instruments
# then dependents) so a merged dependent proposal can resolve an instrument that lives on a
# different import. Per-import transaction; per-proposal failure tolerant; replay-safe via the
# stored `record` GlobalID and pre-create existing-record matching. Phase 1 wires bank_account;
# the other kinds land in Phase 3.
module Imports
  class Apply
    Result = Struct.new(:created, :failed, :skipped, keyword_init: true)

    INSTRUMENT_KINDS = %w[bank_account credit_card].freeze
    DEPENDENT_KINDS  = %w[income commitment].freeze

    def self.call(account:, accepted:)
      new(account, accepted).call
    end

    def initialize(account, accepted)
      @account  = account
      @accepted = accepted.transform_keys(&:to_i)
      @refs     = {}
      @result   = Result.new(created: Hash.new(0), failed: [], skipped: 0)
    end

    def call
      imports = @account.document_imports.awaiting_review.where(id: @accepted.keys).to_a
      preload_refs

      [ INSTRUMENT_KINDS, DEPENDENT_KINDS ].each do |kinds|
        imports.each { |import| apply_import(import, kinds) }
      end
      @result
    end

    private

    def apply_import(import, kinds)
      import.with_lock do
        proposals = import.proposals
        Array(@accepted[import.id]).each do |pid|
          proposal = proposals.find { it["pid"] == pid && kinds.include?(it["kind"]) }
          apply_proposal(proposal, import) if proposal
        end
        import.status = "applied" if proposals.none? { it["state"] == "proposed" }
        import.save!
      end
    end

    def apply_proposal(proposal, import)
      if proposal["state"] == "applied" && locate(proposal["record"])
        @result.skipped += 1
        return
      end

      if (record = existing_match(proposal))
        mark_applied(proposal, record)
        @result.skipped += 1
        return
      end

      record = create_record!(proposal, import)
      mark_applied(proposal, record)
      @result.created[proposal["kind"]] += 1
    rescue ActiveRecord::RecordInvalid => e
      fail_proposal(proposal, e.record.errors.full_messages.to_sentence)
    rescue Imports::MissingInstrument
      fail_proposal(proposal, I18n.t("imports.apply.errors.missing_instrument"))
    end

    def fail_proposal(proposal, message)
      proposal.merge!("state" => "failed", "error" => message)
      @result.failed << { pid: proposal["pid"], kind: proposal["kind"], message: message }
    end

    def mark_applied(proposal, record)
      @refs[proposal["pid"]] = record
      proposal.merge!("state" => "applied", "record" => record.to_global_id.to_s)
    end

    # Seed refs from every previously-applied proposal across the account's imports, so a dependent
    # proposal on one import can resolve an instrument applied on another.
    def preload_refs
      @account.document_imports.where.not(status: "dismissed").find_each do |import|
        import.proposals.each do |proposal|
          next unless proposal["state"] == "applied"

          record = locate(proposal["record"])
          @refs[proposal["pid"]] = record if record
        end
      end
    end

    def create_record!(proposal, import)
      case proposal["kind"]
      when "bank_account" then create_bank_account!(proposal["payload"], import)
      when "credit_card"  then create_credit_card!(proposal["payload"], import)
      when "income"       then create_income!(proposal["payload"], import)
      when "commitment"   then create_commitment!(proposal["payload"], import)
      else raise Imports::Error, "unsupported proposal kind: #{proposal["kind"]}"
      end
    end

    def create_income!(payload, import)
      bank = resolve_instrument(payload["instrument_ref"])
      raise Imports::MissingInstrument unless bank.is_a?(BankAccount)

      @account.incomes.create!(
        created_by:    import.created_by,   # attribution = the member who uploaded (doc 05)
        bank_account:  bank,
        name:          payload["name"],
        amount_cents:  payload["amount_cents"],
        schedule_kind: payload["schedule_kind"].presence || "fixed_day",
        schedule_day:  payload["schedule_day"]
      )
    end

    # source: "import", source_message_id: nil (safe under the partial unique index). Installments
    # create the bare Commitment — NO posted parcel Transactions (that's the v1.1 transaction import);
    # already-elapsed parcels render as presumed-paid from starts_on vs created_at (commitment.rb).
    def create_commitment!(payload, import)
      instrument = resolve_instrument(payload["instrument_ref"])
      attrs = {
        created_by:    import.created_by,   # attribution = the member who uploaded (doc 05)
        name:          payload["name"],
        kind:          payload["commitment_kind"],
        amount_cents:  payload["amount_cents"],
        schedule_kind: payload["schedule_kind"].presence || "fixed_day",
        schedule_day:  payload["schedule_day"],
        starts_on:     parse_date(payload["starts_on"]) || Date.current,
        source:        "import"
      }
      if payload["commitment_kind"] == "installment"
        attrs[:installments_count] = payload["installments_count"]
        attrs[:total_cents]        = payload["total_cents"]
      end
      # Resolved category_guess (auto-categories, Phase 4). Re-checked against the account's
      # kept categories — a stale/foreign id in a replayed proposal is dropped, never raised.
      if payload["category_id"] && @account.categories.kept.exists?(payload["category_id"])
        attrs[:category_id] = payload["category_id"]
      end
      case instrument
      when CreditCard  then attrs[:credit_card]  = instrument
      when BankAccount then attrs[:bank_account] = instrument
      else raise Imports::MissingInstrument
      end
      @account.commitments.create!(attrs)
    end

    def resolve_instrument(ref)
      return nil if ref.blank?

      if ref["pid"] then @refs[ref["pid"]]
      elsif ref["fingerprint"] then match_fingerprint(ref["fingerprint"])
      end
    end

    def match_fingerprint(fingerprint)
      if fingerprint["last4"] then match_credit_card(fingerprint)
      elsif fingerprint["account_number"] then match_bank_account(fingerprint)
      end
    end

    def create_bank_account!(payload, import)
      bank = @account.bank_accounts.create!(
        created_by:     import.created_by,   # attribution = the member who uploaded (doc 05)
        institution:    institution_for(payload["institution_code"]),
        kind:           payload["kind"].presence || "checking",
        nickname:       payload["nickname"].presence,
        agency:         payload["agency"],
        account_number: payload["account_number"],
        balance_cents:  payload["balance_cents"]
      )
      stamp_balance_anchor!(bank, payload["balance_as_of"])
      bank
    end

    # ONE CreditCard per fatura, never per plastic (D5). Billing recompute is NOT called — its only
    # call site is the card UPDATE controller, and a fresh card has zero transactions (credit_card.rb).
    def create_credit_card!(payload, import)
      @account.credit_cards.create!(
        created_by:          import.created_by,   # attribution = the member who uploaded (doc 05)
        institution:         institution_for(payload["institution_code"]),
        last4:               payload["last4"],
        nickname:            payload["nickname"].presence,
        bill_due_day:        payload["bill_due_day"],
        closing_offset_days: payload["closing_offset_days"] || 7,
        credit_limit_cents:  payload["credit_limit_cents"],
        current_bill_cents:  payload["current_bill_cents"]
      )
    end

    # stamp_balance_anchor overwrites balance_anchored_at with Time.current on any balance change
    # (bank_account.rb), so set the document's period-end anchor AFTER create, bypassing the callback.
    def stamp_balance_anchor!(account, as_of)
      date = parse_date(as_of)
      return unless date && account.balance_cents

      account.update_columns(balance_anchored_at: date.end_of_day) # rubocop:disable Rails/SkipsModelValidations
    end

    def existing_match(proposal)
      case proposal["kind"]
      when "bank_account" then match_bank_account(proposal["payload"])
      when "credit_card"  then match_credit_card(proposal["payload"])
      end
    end

    def match_credit_card(payload)
      last4 = Imports.digits(payload["last4"])
      return nil if last4.empty?

      institution = institution_for(payload["institution_code"])
      @account.credit_cards.kept.where(institution: institution).detect { |card| card.last4.to_s == last4 }
    end

    def match_bank_account(payload)
      target = Imports.normalize_account(payload["account_number"])
      return nil if target.empty?

      institution = institution_for(payload["institution_code"])
      @account.bank_accounts.kept.where(institution: institution).detect do |bank|
        Imports.normalize_account(bank.account_number) == target
      end
    end

    def institution_for(code)
      Institution.find_by(code: code) || Institution.find_by(code: Institution::OTHER_CODE)
    end

    def locate(gid)
      return nil if gid.blank?

      record = GlobalID::Locator.locate(gid)
      # A proposal must not link new rows to another account's — or a soft-deleted — instrument.
      record if record.respond_to?(:account_id) && record.account_id == @account.id &&
                !(record.respond_to?(:soft_deleted?) && record.soft_deleted?)
    rescue StandardError
      nil
    end

    # Century guard mirrors DocumentExtractor#full_date: proposals stored before the fix (or a
    # replay of them) may still carry year-00xx ISO strings.
    def parse_date(value)
      return value if value.is_a?(Date)

      date = Date.iso8601(value.to_s)
      date.year < 100 ? date.next_year(2000) : date
    rescue ArgumentError
      nil
    end
  end
end
