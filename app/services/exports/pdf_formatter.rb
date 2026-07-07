module Exports
  # A printable "extrato" (05 §2): account header, period line, one table per month on the
  # occurred_on axis, then per-category spend totals and the net of the range. Pure Ruby
  # (prawn + prawn-table) — deliberately no system dependency. Helvetica is a Windows-1252
  # font, so user text (WhatsApp merchants can carry emoji) is transliterated defensively
  # before drawing.
  class PdfFormatter
    TABLE_COLUMNS = %i[occurred_on description category instrument amount].freeze

    def self.call(ledger) = new(ledger).call

    def initialize(ledger)
      @ledger = ledger
    end

    def call
      Prawn::Fonts::AFM.hide_m17n_warning = true   # UTF-8 input is sanitized in #safe below
      pdf = Prawn::Document.new(page_size: "A4", margin: 36)
      pdf.font "Helvetica"
      header(pdf)
      months.each { |month, rows| month_section(pdf, month, rows) }
      totals_section(pdf)
      pdf.render
    end

    private
      def months
        @ledger.rows.group_by { |row| row.occurred_on.beginning_of_month }
      end

      def header(pdf)
        pdf.text safe(I18n.t("exports.pdf.title", account: @ledger.account.name)),
                 size: 16, style: :bold
        pdf.text safe(period_line), size: 10, color: "555555"
        pdf.move_down 16
      end

      # A missing bound falls back to the data's own span ("tudo"); an empty range says so.
      def period_line
        from = @ledger.from || @ledger.rows.first&.occurred_on
        to   = @ledger.to   || @ledger.rows.last&.occurred_on
        return I18n.t("exports.pdf.period_empty") unless from && to
        I18n.t("exports.pdf.period", from: I18n.l(from), to: I18n.l(to))
      end

      def month_section(pdf, month, rows)
        pdf.text safe(I18n.l(month, format: :month_year)), size: 12, style: :bold
        pdf.move_down 4
        data = [ table_header ] + rows.map { |row| table_values(row) }
        pdf.table(data, header: true, width: pdf.bounds.width,
                        cell_style: { size: 8, borders: [ :bottom ], border_color: "DDDDDD",
                                      padding: [ 3, 4 ] }) do |table|
          table.row(0).font_style = :bold
          table.column(-1).align = :right
        end
        pdf.move_down 16
      end

      def table_header
        TABLE_COLUMNS.map { |column| safe(I18n.t("exports.ledger.headers.#{column}")) }
      end

      def table_values(row)
        [
          I18n.l(row.occurred_on),
          safe(row.description),
          safe(row.category),
          safe(row.instrument),
          currency(row.amount_cents)
        ]
      end

      def totals_section(pdf)
        totals = category_totals
        if totals.any?
          pdf.text safe(I18n.t("exports.pdf.by_category")), size: 12, style: :bold
          pdf.move_down 4
          data = totals.map { |name, cents| [ safe(name), currency(cents.abs) ] }
          pdf.table(data, width: pdf.bounds.width,
                          cell_style: { size: 8, borders: [ :bottom ], border_color: "DDDDDD",
                                        padding: [ 3, 4 ] }) { |table| table.column(-1).align = :right }
          pdf.move_down 12
        end
        pdf.text safe(I18n.t("exports.pdf.net_total", amount: currency(@ledger.total_cents))),
                 size: 11, style: :bold
      end

      # Spend by category (expenses only), biggest first; uncategorized rows get a bucket.
      def category_totals
        @ledger.rows.select { |row| row.direction == "expense" }
               .group_by { |row| row.category || I18n.t("transactions.ledger.uncategorized") }
               .transform_values { |rows| rows.sum(&:amount_cents) }
               .sort_by { |_, cents| cents }
      end

      def currency(cents)
        ActiveSupport::NumberHelper.number_to_currency(Exports.money(cents),
                                                       unit: I18n.t("money.symbol"))
      end

      # Helvetica covers Windows-1252 only: map the transfer arrow, then drop anything the
      # font cannot draw (emoji in WhatsApp-captured merchants) instead of crashing prawn.
      def safe(text)
        text.to_s.gsub("→", "->")
            .encode(Encoding::WINDOWS_1252, invalid: :replace, undef: :replace, replace: "")
            .encode(Encoding::UTF_8)
      end
  end
end
