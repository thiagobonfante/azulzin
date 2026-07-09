module MoneyHelper
  # Formats integer cents as Brazilian currency. The amount is always BRL, so we pin the
  # R$ unit (via money.symbol) instead of inheriting it from the locale — otherwise en-US
  # would render "$", showing reais as dollars. Separators still localize per UI language.
  # BigDecimal keeps the conversion exact.
  def brl(cents)
    number_to_currency(BigDecimal(cents.to_i) / 100, unit: t("money.symbol"))
  end

  # Whole-real variant for the goals UI (round 3 P1 — no cents there). :ceil for figures
  # the user is ASKED to save/aim for (never under-ask); :floor for capacity/achievable
  # figures and real ledger amounts (never overstate what the household has/can do).
  def brl_whole(cents, mode: :ceil)
    rounded = mode == :floor ? Money.floor_to_real(cents) : Money.ceil_to_real(cents)
    number_to_currency(BigDecimal(rounded.to_i) / 100, unit: t("money.symbol"), precision: 0)
  end
end
