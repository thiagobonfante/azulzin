module Exports
  # Locale-aware CSV (05 §2): a pt-BR Excel expects `;` as the field delimiter (`,` is the
  # decimal separator there); en gets a plain `,`. The UTF-8 BOM is emitted for BOTH locales —
  # the data can carry acentos regardless of the viewer's language, and Excel needs the BOM
  # to decode them. Money cells are plain localized decimals (no symbol, no grouping) so
  # spreadsheets can sum them.
  class CsvFormatter
    BOM = "\uFEFF"

    # Formula-injection guard: a cell starting with = + - @ TAB or CR executes as a formula
    # when the CSV is opened in Excel/LibreOffice. User-controlled text columns (description,
    # category, instrument) get a leading apostrophe; the amount column is never guarded —
    # its legitimate negatives must stay bare numbers.
    FORMULA_TRIGGERS = /\A[=+\-@\t\r]/

    def self.call(ledger)
      body = CSV.generate(col_sep: I18n.locale == :"pt-BR" ? ";" : ",") do |csv|
        csv << Exports::COLUMNS.map { |column| I18n.t("exports.ledger.headers.#{column}") }
        ledger.rows.each { |row| csv << values_for(row) }
      end
      BOM + body
    end

    def self.values_for(row)
      [
        I18n.l(row.occurred_on),
        I18n.l(row.billing_month, format: :month_year),
        guard(row.description),
        guard(row.category),
        row.kind,
        ActiveSupport::NumberHelper.number_to_rounded(Exports.money(row.amount_cents),
                                                      precision: 2, delimiter: ""),
        guard(row.instrument),
        row.status
      ]
    end

    def self.guard(text)
      text.is_a?(String) && text.match?(FORMULA_TRIGGERS) ? "'#{text}" : text
    end
  end
end
