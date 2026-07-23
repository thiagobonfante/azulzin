# "Conferir com o banco" (.plans/credit-cards 03): one LLM-free diff engine fed by
# adapters — the PDF extraction today, Pluggy rows tomorrow (they arrive with external_id
# set; the engine doesn't know or care that the source changed). Matching is deterministic
# and free; the AI cap applies only to the PDF-extraction adapter upstream.
module Reconciliation
  # The adapter contract: one normalized statement line.
  Row = Struct.new(:date, :description, :amount_cents, :direction, :installment,
                   :section_last4, :external_id, keyword_init: true) do
    # Content-derived identity — the replay-safe dedup key for created transactions
    # (rides source_message_id's existing unique index, the WA idiom).
    def digest
      Digest::SHA1.hexdigest([ date, description, amount_cents, direction, installment ].join("|"))
    end

    # "PARC 03/10" → 3; nil when the line isn't a parcel.
    def parcel_number
      installment.to_s[/(\d+)\s*\/\s*\d+/, 1]&.to_i
    end
  end

  # Extraction rows (Imports::DocumentExtractor / CsvParser shape) → [Row]. Rows the
  # extractor couldn't date are kept — they can never match, so they surface honestly
  # in the only-in-source bucket instead of vanishing.
  def self.rows_from_extraction(extraction)
    Array(extraction["rows"]).map do |row|
      Row.new(
        date:          (Date.iso8601(row["date"]) rescue nil),
        description:   row["description"].to_s,
        amount_cents:  row["amount_cents"].to_i,
        direction:     row["direction"] == "in" ? "income" : "expense",
        installment:   row["installment"],
        section_last4: row["section_last4"],
        external_id:   row["external_id"])
    end
  end
end
