require "csv"
require "bigdecimal"

# Nubank layout (`Data,Valor,Identificador,Descrição`; DD/MM/YYYY; dot-decimal despite pt-BR;
# UUID identifier), written defensively for other banks. Nubank CSVs carry NO account header —
# identity comes from the OFX twin (§8 meta is {}). Returns the normalized-row contract (§8).
module Imports
  module CsvParser
    module_function

    HEADER_SCAN_LINES = 10

    def call(bytes)
      text  = table_text(Imports.decode(bytes))
      sep   = detect_separator(text)
      table = CSV.parse(text, headers: true, col_sep: sep, skip_blanks: true, liberal_parsing: true)
      raise ParseError, "empty csv" if table.headers.compact.empty?

      map = header_map(table.headers)
      raise ParseError, "no date/amount columns" unless map[:date] && (map[:amount] || map[:credit] || map[:debit])

      dot = dot_decimal?(table, map)
      rows = table.filter_map { |row| parse_row(row, map, dot) }
      { "format" => "csv", "meta" => {}, "rows" => rows }
    rescue CSV::MalformedCSVError
      raise ParseError, "malformed csv"
    end

    # Bank CSVs (Bradesco, Caixa) often prepend title/account preamble lines before the actual
    # table — start at the first line that reads like a header row, so column mapping sees real
    # headers instead of the preamble.
    def table_text(text)
      lines = text.lines
      index = lines.first(HEADER_SCAN_LINES).index { |line| header_like?(line) }
      index.to_i.positive? ? lines[index..].join : text
    end

    def header_like?(line)
      (line.include?(";") || line.include?(",")) &&
        Imports.strip_accents(line.downcase).match?(FormatDetector::KNOWN_HEADER)
    end

    def detect_separator(text)
      header = text.lines.first.to_s
      header.count(";") > header.count(",") ? ";" : ","
    end

    def header_map(headers)
      map = {}
      headers.each do |header|
        next if header.nil?

        case Imports.strip_accents(header.to_s.downcase.strip)
        when /identificador|\bfitid\b/       then map[:external_id] ||= header
        when /\bdata\b|date/                 then map[:date] ||= header
        when /valor|amount|value/            then map[:amount] ||= header
        when /credito|\bcredit\b/            then map[:credit] ||= header
        when /debito|\bdebit\b/              then map[:debit] ||= header
        when /descri|historico|memo|lancamento/ then map[:description] ||= header
        end
      end
      map
    end

    # Whole-FILE decision (never per row): dot-decimal only when EVERY amount matches N or N.NN
    # and none carries a comma — otherwise the pt-BR path (Money.to_cents) handles "1.234,56".
    def dot_decimal?(table, map)
      cols    = amount_headers(map)
      amounts = table.flat_map { |r| cols.filter_map { |c| r[c]&.strip.presence } }
      amounts.any? && amounts.all? { it.match?(/\A-?\d+(\.\d{1,2})?\z/) } && amounts.none? { it.include?(",") }
    end

    def amount_headers(map)
      map[:amount] ? [ map[:amount] ] : [ map[:credit], map[:debit] ].compact
    end

    # Single signed "Valor" column, or the split "Crédito (R$)"/"Débito (R$)" pair some banks
    # (Bradesco) export — a filled débito cell forces direction out, crédito forces in. A literal
    # zero placeholder ("0,00") in the unused cell counts as empty, not as a debit.
    def amount_field(row, map)
      return [ row[map[:amount]].to_s.strip, nil ] if map[:amount]

      debit = map[:debit] && split_cell(row[map[:debit]])
      return [ debit, "out" ] if debit.present?

      [ (map[:credit] ? split_cell(row[map[:credit]]) : ""), "in" ]
    end

    def split_cell(value)
      v = value.to_s.strip
      v.match?(/\A-?0+([.,]0+)?\z/) ? "" : v
    end

    def parse_row(row, map, dot)
      raw_amount, forced_direction = amount_field(row, map)
      cents = if dot
        raw_amount.empty? ? nil : (BigDecimal(raw_amount) * 100).to_i
      else
        Money.to_cents(raw_amount)
      end
      cents ||= 0
      date = parse_date(row[map[:date]])
      {
        "date"         => date&.iso8601,
        "description"  => row[map[:description]].to_s.gsub(/\s+/, " ").strip,
        "amount_cents" => cents.abs,
        "direction"    => forced_direction || (cents.negative? ? "out" : "in"),
        "external_id"  => row[map[:external_id]]&.strip.presence,
        "raw"          => row.to_h.transform_keys(&:to_s),
        "signals"      => date ? [] : [ "date_unparsed" ]
      }
    end

    def parse_date(value)
      v = value.to_s.strip
      return nil if v.empty?

      Date.strptime(v, "%d/%m/%Y")
    rescue ArgumentError
      Date.iso8601(v) rescue nil
    end
  end
end
