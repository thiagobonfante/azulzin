# Data export (up-tier F4 — .plans/up-tier/05): one row builder (Exports::Ledger) feeding
# one formatter per file format. Money stays integer cents until the last moment, then
# becomes BigDecimal — never floats (house grep gate).
module Exports
  # Export column keys, in output order. Header labels live at exports.ledger.headers.*
  # in both locale files.
  COLUMNS = %i[occurred_on billing_month description category kind amount instrument status].freeze

  # Integer cents → BigDecimal reais, exact.
  def self.money(cents) = BigDecimal(cents.to_i) / 100
end
