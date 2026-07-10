# Never trust the extension or the client content type — the sample fatura has no extension at
# all, and browsers label CSV as application/vnd.ms-excel. Detection is over the raw bytes.
module Imports
  module FormatDetector
    module_function

    KNOWN_HEADER = /\b(data|valor|descricao|historico|identificador|lancamento|movimento|credito|debito)\b/

    def call(bytes, filename: nil)
      head = bytes.to_s[0, 2048].to_s
      return "pdf" if head.include?("%PDF-")
      return "ofx" if head.match?(/OFXHEADER|<OFX>/i)
      return "csv" if csv_like?(bytes)

      nil
    end

    def csv_like?(bytes)
      lines = Imports.decode(bytes.to_s[0, 4096]).lines.first(10).map(&:strip).reject(&:empty?)
      return false if lines.empty?

      # A known header row anywhere near the top counts — bank CSVs (Bradesco, Caixa) prepend
      # title/account preamble lines; CsvParser skips them the same way.
      return true if lines.any? do |line|
        (line.include?(";") || line.include?(",")) && Imports.strip_accents(line.downcase).match?(KNOWN_HEADER)
      end

      header = lines.first
      sep    = header.count(";") > header.count(",") ? ";" : ","
      cols   = header.split(sep).size
      return false if cols < 2

      lines.first(5).count { it.split(sep).size == cols } >= ([ lines.size, 5 ].min * 0.8)
    end
  end
end
