require "csv"
require "bigdecimal"

# Nubank layout (`Data,Valor,Identificador,Descrição`; DD/MM/YYYY; dot-decimal despite pt-BR;
# UUID identifier), written defensively for other banks. Nubank CSVs carry NO account header —
# identity comes from the OFX twin (§8 meta is {}). Returns the normalized-row contract (§8).
module Imports
  module CsvParser
    module_function

    def call(bytes)
      text  = Imports.decode(bytes)
      sep   = detect_separator(text)
      table = CSV.parse(text, headers: true, col_sep: sep, skip_blanks: true)
      raise ParseError, "empty csv" if table.headers.compact.empty?

      map = header_map(table.headers)
      raise ParseError, "no date/amount columns" unless map[:date] && map[:amount]

      dot = dot_decimal?(table, map)
      rows = table.filter_map { |row| parse_row(row, map, dot) }
      { "format" => "csv", "meta" => {}, "rows" => rows }
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
        when /descri|historico|memo|lancamento/ then map[:description] ||= header
        end
      end
      map
    end

    # Whole-FILE decision (never per row): dot-decimal only when EVERY amount matches N or N.NN
    # and none carries a comma — otherwise the pt-BR path (Money.to_cents) handles "1.234,56".
    def dot_decimal?(table, map)
      amounts = table.filter_map { |r| r[map[:amount]]&.strip.presence }
      amounts.any? && amounts.all? { it.match?(/\A-?\d+(\.\d{1,2})?\z/) } && amounts.none? { it.include?(",") }
    end

    def parse_row(row, map, dot)
      raw_amount = row[map[:amount]].to_s.strip
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
        "direction"    => cents.negative? ? "out" : "in",
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
