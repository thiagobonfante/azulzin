# Read-side helper for the ONE review page (D6): collects `proposed` items across ALL the user's
# extracted imports and dedupes by pid (content-derived identity — the CSV/OFX twins and repeated
# uploads collapse to one row), grouped by kind in display order. Cross-file merge of
# income/commitment candidates lands in Phase 3.
module Imports
  module Review
    GROUP_ORDER = %w[bank_account credit_card income commitment].freeze

    module_function

    def groups(imports)
      by_pid = {}
      imports.each do |import|
        import.proposals.each do |proposal|
          next unless proposal["state"] == "proposed"

          current = by_pid[proposal["pid"]]
          by_pid[proposal["pid"]] = proposal if current.nil? ||
            proposal["confidence"].to_f > current["confidence"].to_f
        end
      end

      by_pid.values
            .group_by { it["kind"] }
            .sort_by { |kind, _| GROUP_ORDER.index(kind) || GROUP_ORDER.size }
            .to_h
    end

    def any?(imports)
      imports.any? { |import| import.proposals.any? { it["state"] == "proposed" } }
    end
  end
end
