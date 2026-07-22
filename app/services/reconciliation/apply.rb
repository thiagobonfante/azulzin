module Reconciliation
  # The commit point of a reconciliation run (.plans/credit-cards 03 §2): NOTHING
  # auto-applies — this receives only what the user accepted on the review page, re-runs
  # the deterministic diff against live data, and acts on the intersection. Idempotent:
  # created rows carry source "reconciliation" + a content-derived source_message_id
  # ("recon-{import}-{digest}") so replaying a run creates zero new rows (the existing
  # unique index does the work, same idiom as WA dedup).
  class Apply
    Result = Struct.new(:created, :moved, :fixed, :skipped, keyword_init: true)

    def self.call(import:, scope:, accepted:, created_by: nil)
      new(import, scope, accepted, created_by).call
    end

    def initialize(import, scope, accepted, created_by)
      @import     = import
      @scope      = scope
      @accepted   = accepted
      @created_by = created_by
      @result     = Result.new(created: 0, moved: 0, fixed: 0, skipped: 0)
    end

    def call
      diff = Diff.call(rows: Reconciliation.rows_from_extraction(@import.extraction), scope: @scope)
      diff.only_in_source.each { |row| create!(row) if accepted?(:create, row.digest) }
      diff.only_in_app.each { |txn| move!(txn) if accepted?(:move, txn.id) }
      diff.amount_mismatch.each { |row, txn| fix!(row, txn) if accepted?(:fix, txn.id) }
      @import.update!(status: "applied")
      @result
    end

    private

    def accepted?(action, key) = Array(@accepted[action]).include?(key.to_s)

    def create!(row)
      category_id, category_source = Categories.auto_assign(
        account: @import.account, merchant: row.description, label: nil)   # memory only — no LLM here
      @import.account.transactions.create!(
        created_by:        @created_by,
        merchant:          row.description,
        direction:         row.direction,
        status:            "posted",
        confirmed_at:      Time.current,
        amount_cents:      row.amount_cents,
        occurred_on:       row.date,
        credit_card:       @scope.credit_card,
        billing_month:     @scope.month,
        billing_month_manual: true,   # the bank put it on THIS bill — never re-bucket it
        category_id:       category_id,
        category_source:   category_source,
        source:            "reconciliation",
        source_message_id: "recon-#{@import.id}-#{row.digest}")
      @result.created += 1
    rescue ActiveRecord::RecordNotUnique
      @result.skipped += 1   # replayed run — the row already exists
    end

    def move!(txn)
      txn.update!(billing_month: @scope.move_month, billing_month_manual: true)
      @result.moved += 1
    end

    def fix!(row, txn)
      txn.update!(amount_cents: row.amount_cents)   # Attributable stamps the audit trail
      @result.fixed += 1
    end
  end
end
