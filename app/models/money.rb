# Parses human-typed money into integer cents (the app stores money as cents, never
# floats — see CLAUDE.md). Tolerant of pt-BR ("1.234,56"), en-US ("1,234.56") and plain
# ("1234.56" / "1234,56" / "1234") input.
module Money
  module_function

  # The last comma or dot followed by 1–2 digits is the decimal separator; any other
  # separators are thousands grouping. Blank or non-numeric input returns nil.
  def to_cents(input)
    return nil if input.nil?

    s = input.to_s.strip.gsub(/[^\d.,-]/, "")
    negative = s.start_with?("-")
    s = s.delete("-")
    return nil if s.empty?

    last_sep = [ s.rindex(","), s.rindex(".") ].compact.max
    cents =
      if last_sep && (1..2).cover?(s.length - last_sep - 1)
        whole = s[0...last_sep].gsub(/[.,]/, "")
        frac  = s[(last_sep + 1)..].ljust(2, "0")
        whole.to_i * 100 + frac.to_i
      else
        s.gsub(/[.,]/, "").to_i * 100
      end

    negative ? -cents : cents
  end
end
