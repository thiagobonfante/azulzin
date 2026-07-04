module MoneyHelper
  # Formats integer cents as Brazilian currency. The amount is always BRL, so we pin the
  # R$ unit (via money.symbol) instead of inheriting it from the locale — otherwise en-US
  # would render "$", showing reais as dollars. Separators still localize per UI language.
  # BigDecimal keeps the conversion exact.
  def brl(cents)
    number_to_currency(BigDecimal(cents.to_i) / 100, unit: t("money.symbol"))
  end
end
