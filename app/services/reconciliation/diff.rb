module Reconciliation
  # The deterministic matcher (.plans/credit-cards 03 §2). Greedy unique assignment,
  # best-first: exact amount + direction, date within ±3 days, description similarity as
  # the tiebreaker; parcel lines must also agree on k. A second pass pairs what's left by
  # date + merchant alone when only the cents differ (the "89,90 vs 88,90" typo case).
  # Adversarial shapes (two same-amount same-day rows, estornos) are pinned in tests.
  class Diff
    Result = Struct.new(:matched, :only_in_source, :only_in_app, :amount_mismatch, keyword_init: true)

    DATE_WINDOW_DAYS     = 3
    MISMATCH_SIMILARITY  = 0.6   # "merchant agrees" for the typo pass — deliberately high

    def self.call(rows:, scope:)
      new(rows, scope).call
    end

    def initialize(rows, scope)
      @rows  = rows
      @scope = scope
      @txns  = scope.transactions.to_a
    end

    def call
      matched  = assign(exact_candidates)
      leftover_rows = @rows - matched.map(&:first)
      leftover_txns = @txns - matched.map(&:last)
      mismatched = assign(mismatch_candidates(leftover_rows, leftover_txns))

      Result.new(
        matched:         matched,
        amount_mismatch: mismatched,
        only_in_source:  leftover_rows - mismatched.map(&:first),
        only_in_app:     leftover_txns - mismatched.map(&:last))
    end

    private

    # [similarity, row, txn] for every exact-amount pair inside the window.
    def exact_candidates
      pairs(@rows, @txns) do |row, txn|
        next unless txn.amount_cents == row.amount_cents
        next if row.parcel_number && txn.installment_number && row.parcel_number != txn.installment_number
        similarity(row, txn)
      end
    end

    # Same date+direction discipline, cents DISAGREE, description must clearly agree.
    def mismatch_candidates(rows, txns)
      pairs(rows, txns) do |row, txn|
        next if txn.amount_cents == row.amount_cents
        score = similarity(row, txn)
        score if score >= MISMATCH_SIMILARITY
      end
    end

    def pairs(rows, txns)
      candidates = []
      rows.each do |row|
        next unless row.date
        txns.each do |txn|
          next unless @scope.direction_of(txn) == row.direction
          next if (txn.occurred_on - row.date).abs > DATE_WINDOW_DAYS
          score = yield(row, txn)
          candidates << [ score, row, txn ] if score
        end
      end
      candidates
    end

    # Best pair first (higher similarity, then closer dates), each row/txn used once.
    def assign(candidates)
      taken_rows, taken_txns, out = Set.new, Set.new, []
      candidates.sort_by { |score, row, txn| [ -score, (txn.occurred_on - row.date).abs ] }.each do |_, row, txn|
        next if taken_rows.include?(row.object_id) || taken_txns.include?(txn.id)
        taken_rows << row.object_id
        taken_txns << txn.id
        out << [ row, txn ]
      end
      out
    end

    def similarity(row, txn)
      TextMatch.similarity(TextMatch.normalize(row.description),
                           txn.merchant_norm.presence || TextMatch.normalize(txn.merchant))
    end
  end
end
