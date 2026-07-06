# Cross-document reconciliation (§9, zero LLM), run over all the account's extracted imports when
# building the review payload. v1 scope: suppress income proposals that are really self-transfers
# — a credit on account A that pairs with an equal debit on account B within a couple days (the
# classifier usually labels obvious transfers itself; this catches the ones a big credit fools).
# Commitment de-dup across the CSV/OFX twins is handled upstream by content-derived pids.
module Imports
  module Reconciler
    module_function

    SKEW_DAYS = 2

    def call(account)
      imports = account.document_imports.awaiting_review.to_a
      suppress_self_transfers(imports)
      imports
    end

    def suppress_self_transfers(imports)
      debits = imports.flat_map do |import|
        Array(import.extraction&.dig("rows")).filter_map do |row|
          next unless row["direction"] == "out" && (date = parse(row["date"]))

          { import_id: import.id, date: date, amount_cents: row["amount_cents"] }
        end
      end

      imports.each do |import|
        changed = false
        import.proposals.each do |proposal|
          next unless proposal["kind"] == "income" && proposal["state"] == "proposed"
          next unless paired_transfer?(proposal, import.id, debits)

          proposal["state"] = "rejected"
          changed = true
        end
        import.save! if changed
      end
    end

    # A matching debit of the same amount, in a DIFFERENT import, within the settlement skew.
    def paired_transfer?(proposal, income_import_id, debits)
      evidence = Array(proposal["evidence"]).first
      return false unless evidence

      date   = parse(evidence["date"])
      amount = evidence["amount_cents"]
      return false unless date && amount

      debits.any? do |debit|
        debit[:import_id] != income_import_id &&
          debit[:amount_cents] == amount &&
          (debit[:date] - date).abs <= SKEW_DAYS
      end
    end

    def parse(iso)
      Date.iso8601(iso.to_s)
    rescue ArgumentError, Date::Error
      nil
    end
  end
end
