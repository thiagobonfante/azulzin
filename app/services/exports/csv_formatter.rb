module Exports
  # Locale-aware CSV (05 §2): a pt-BR Excel expects `;` as the field delimiter (`,` is the
  # decimal separator there) plus a UTF-8 BOM to render acentos; en gets a plain `,` and no
  # BOM. Money cells are plain localized decimals (no symbol, no grouping) so spreadsheets
  # can sum them.
  class CsvFormatter
    BOM = "\uFEFF"

    def self.call(ledger)
      pt_br = I18n.locale == :"pt-BR"
      body = CSV.generate(col_sep: pt_br ? ";" : ",") do |csv|
        csv << Exports::COLUMNS.map { |column| I18n.t("exports.ledger.headers.#{column}") }
        ledger.rows.each { |row| csv << values_for(row) }
      end
      pt_br ? BOM + body : body
    end

    def self.values_for(row)
      [
        I18n.l(row.occurred_on),
        I18n.l(row.billing_month, format: :month_year),
        row.description,
        row.category,
        row.kind,
        ActiveSupport::NumberHelper.number_to_rounded(Exports.money(row.amount_cents),
                                                      precision: 2, delimiter: ""),
        row.instrument,
        row.status
      ]
    end
  end
end
