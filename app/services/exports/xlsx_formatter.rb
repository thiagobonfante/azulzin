module Exports
  # caxlsx workbook (05 §2): one frozen, localized header row; money cells are real numbers
  # (BigDecimal — spreadsheets can sum them) wearing a currency format; a bold totals block.
  # Assembled to a StringIO for send_data. Dates use Excel's locale-aware short-date format
  # (num_fmt 14) so the viewer's locale decides the rendering.
  class XlsxFormatter
    # occurred_on · billing_month · description · category · kind · amount · instrument · status
    # :float is the accepted exception to the house no-float rule: caxlsx casts numeric cells
    # via to_f internally — that's the XLSX file format itself, and IEEE doubles are cent-exact
    # at any realistic money magnitude; our code hands it BigDecimal and never touches floats.
    CELL_TYPES = %i[date string string string string float string string].freeze
    # User text lands in string-typed cells (never formulas), so the CSV formula-injection
    # guard is unnecessary here — safe by construction.

    def self.call(ledger) = new(ledger).call

    def initialize(ledger)
      @ledger = ledger
    end

    def call
      package = Axlsx::Package.new
      build_worksheet(package.workbook)
      package.to_stream.read
    end

    private
      def build_worksheet(workbook)
        header = workbook.styles.add_style(b: true)
        date   = workbook.styles.add_style(num_fmt: 14)
        money  = workbook.styles.add_style(format_code: money_format)
        total  = workbook.styles.add_style(b: true, format_code: money_format)

        workbook.add_worksheet(name: I18n.t("exports.ledger.sheet_name")) do |sheet|
          sheet.add_row(headers, style: header)
          @ledger.rows.each do |row|
            sheet.add_row(values_for(row), types: CELL_TYPES,
                          style: [ date, nil, nil, nil, nil, money, nil, nil ])
          end
          totals_rows.each do |label, cents|
            sheet.add_row([ label, nil, nil, nil, nil, Exports.money(cents), nil, nil ],
                          style: [ header, nil, nil, nil, nil, total, nil, nil ])
          end
          freeze_header(sheet)
        end
      end

      def headers
        Exports::COLUMNS.map { |column| I18n.t("exports.ledger.headers.#{column}") }
      end

      def values_for(row)
        [
          row.occurred_on,
          I18n.l(row.billing_month, format: :month_year),
          row.description,
          row.category,
          row.kind,
          Exports.money(row.amount_cents),
          row.instrument,
          row.status
        ]
      end

      # Labelled totals block (signed cents, like the data rows). Resultado excludes
      # transfers — the hub's cash-flow meaning (see Exports::Ledger#result_cents).
      def totals_rows
        [
          [ I18n.t("exports.ledger.totals.income"),    @ledger.income_cents ],
          [ I18n.t("exports.ledger.totals.expenses"),  @ledger.expense_cents ],
          [ I18n.t("exports.ledger.totals.transfers"), @ledger.transfer_cents ],
          [ I18n.t("exports.ledger.totals.result"),    @ledger.result_cents ]
        ]
      end

      # Money is always BRL — the symbol is pinned via money.symbol (same rationale as
      # MoneyHelper#brl); the separators in the format code localize in the viewer's Excel.
      def money_format = %("#{I18n.t("money.symbol")}" #,##0.00)

      def freeze_header(sheet)
        sheet.sheet_view.pane do |pane|
          pane.top_left_cell = "A2"
          pane.state         = :frozen
          pane.y_split       = 1
        end
      end
  end
end
