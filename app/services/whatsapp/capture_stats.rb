module Whatsapp
  # Per-modality capture health — the data gate for tuning Confidence.floor and
  # Extraction#modality_factor ("start HIGH and lower it as the in-app correction rate
  # proves the extraction trustworthy"). Read-only: each row is compared against the
  # extraction frozen at capture time, so a later human edit shows up as a correction.
  # Population = rows with a non-nil confidence, i.e. exactly the set scored by
  # Confidence and gated by the floor (income/transfer/etc. don't gate on it).
  # Run with: bin/rails whatsapp:capture_stats [SINCE_DAYS=90]
  module CaptureStats
    SOURCES = %w[whatsapp_text whatsapp_audio whatsapp_receipt].freeze

    module_function

    def call(since: 90.days.ago)
      SOURCES.index_with { |source| for_source(source, since) }
    end

    def for_source(source, since)
      floor = Whatsapp::Confidence.floor
      rows  = Transaction.where(source: source, created_at: since..)
                         .where.not(confidence: nil)
                         .pluck(:confidence, :amount_cents, :merchant, :extraction, :deleted_at)
      return { total: 0 } if rows.empty?

      auto = rows.select { |conf, *| conf >= floor }
      {
        total:       rows.size,
        auto_posted: auto.size,
        asked:       rows.count { |conf, *| conf.zero? },          # ≈ "quanto foi?" (score 0 ⇔ no amount)
        parked:      rows.count { |conf, *| conf.positive? && conf < floor },
        # Corrections on auto-posted rows only — the floor's false-positive rate.
        amount_corrected:   auto.count { |_, cents, _, ex, _| ex["amount_cents"].present? && ex["amount_cents"] != cents },
        merchant_corrected: auto.count { |_, _, merchant, ex, _| ex.key?("merchant") && ex["merchant"] != merchant },
        undone:             auto.count { |*, deleted_at| deleted_at.present? },
        avg_confidence:     (rows.sum { |conf, *| conf } / rows.size.to_f).round(1)
      }
    end
  end
end
