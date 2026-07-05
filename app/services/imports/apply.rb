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

    def self.call(user:, accepted:)
      new(user, accepted).call
    end

    def initialize(user, accepted)
      @user     = user
      @accepted = accepted.transform_keys(&:to_i)
      @refs     = {}
      @result   = Result.new(created: Hash.new(0), failed: [], skipped: 0)
    end

    def call
      imports = @user.document_imports.awaiting_review.where(id: @accepted.keys).to_a
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
          apply_proposal(proposal) if proposal
        end
        import.status = "applied" if proposals.none? { it["state"] == "proposed" }
        import.save!
      end
    end

    def apply_proposal(proposal)
      if proposal["state"] == "applied" && locate(proposal["record"])
        @result.skipped += 1
        return
      end

      if (record = existing_match(proposal))
        mark_applied(proposal, record)
        @result.skipped += 1
        return
      end

      record = create_record!(proposal)
      mark_applied(proposal, record)
      @result.created[proposal["kind"]] += 1
    rescue ActiveRecord::RecordInvalid => e
      proposal.merge!("state" => "failed", "error" => e.record.errors.full_messages.to_sentence)
      @result.failed << { pid: proposal["pid"], kind: proposal["kind"], message: proposal["error"] }
    end

    def mark_applied(proposal, record)
      @refs[proposal["pid"]] = record
      proposal.merge!("state" => "applied", "record" => record.to_global_id.to_s)
    end

    # Seed refs from every previously-applied proposal across the user's imports, so a dependent
    # proposal on one import can resolve an instrument applied on another.
    def preload_refs
      @user.document_imports.where.not(status: "dismissed").find_each do |import|
        import.proposals.each do |proposal|
          next unless proposal["state"] == "applied"

          record = locate(proposal["record"])
          @refs[proposal["pid"]] = record if record
        end
      end
    end

    def create_record!(proposal)
      case proposal["kind"]
      when "bank_account" then create_bank_account!(proposal["payload"])
      else raise Imports::Error, "unsupported proposal kind: #{proposal["kind"]}"
      end
    end

    def create_bank_account!(payload)
      account = @user.bank_accounts.create!(
        institution:    institution_for(payload["institution_code"]),
        kind:           payload["kind"].presence || "checking",
        nickname:       payload["nickname"].presence,
        agency:         payload["agency"],
        account_number: payload["account_number"],
        balance_cents:  payload["balance_cents"]
      )
      stamp_balance_anchor!(account, payload["balance_as_of"])
      account
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
      end
    end

    def match_bank_account(payload)
      target = Imports.normalize_account(payload["account_number"])
      return nil if target.empty?

      institution = institution_for(payload["institution_code"])
      @user.bank_accounts.where(institution: institution).detect do |account|
        Imports.normalize_account(account.account_number) == target
      end
    end

    def institution_for(code)
      Institution.find_by(code: code) || Institution.find_by(code: Institution::OTHER_CODE)
    end

    def locate(gid)
      return nil if gid.blank?

      record = GlobalID::Locator.locate(gid)
      record if record.respond_to?(:user_id) && record.user_id == @user.id
    rescue StandardError
      nil
    end

    def parse_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
