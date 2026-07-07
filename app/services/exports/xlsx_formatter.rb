module Exports
  # caxlsx workbook (05 §2): one frozen, localized header row; money cells are real numbers
  # (BigDecimal — spreadsheets can sum them) wearing a currency format; a bold totals row.
  # Assembled to a StringIO for send_data. Dates use Excel's locale-aware short-date format
  # (num_fmt 14) so the viewer's locale decides the rendering.
  class XlsxFormatter
    # occurred_on · billing_month · description · category · kind · amount · instrument · status
    CELL_TYPES = %i[date string string string string float string string].freeze

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
          sheet.add_row(totals_row, style: [ header, nil, nil, nil, nil, total, nil, nil ])
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

      def totals_row
        [ I18n.t("exports.ledger.total"), nil, nil, nil, nil,
          Exports.money(@ledger.total_cents), nil, nil ]
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
