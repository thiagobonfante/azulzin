import { Controller } from "@hotwired/stimulus"

// Money input mask, attached directly to the <input> (no currency symbol — the R$ prefix
// span is in the markup). Two modes:
//
// Default (whole reais, round 3 P1 — goals asks whole reais, no cents): digits only,
// re-rendered with locale thousands grouping. The server must prefill the input with a
// WHOLE-REAL string (never the default *_reais "60000,00" — a digits-only mask would read
// that ×100); Money.to_cents already parses "60.000"/"60,000" as whole reais.
//
// cents mode (`data-money-mask-cents-value="true"`, the *_reais cents inputs): digits are
// centavos, bank-app style — typing 8750 renders "87,50". The default `_reais` prefill
// ("480,00") re-masks to itself, and a leading minus survives (negative balances).
// Money.to_cents parses the masked output in both locales ("1.092,00" / "1,092.00").
export default class extends Controller {
  static values = { cents: Boolean }

  connect() { this.format() }

  format() {
    const negative = this.centsValue && this.element.value.trimStart().startsWith("-")
    const digits = this.element.value.replace(/\D/g, "")
    if (digits === "") {
      this.element.value = negative ? "-" : ""
      return
    }
    const locale = document.documentElement.lang || "pt-BR"
    this.element.value = this.centsValue
      ? (negative ? "-" : "") + new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(parseInt(digits, 10) / 100)
      : new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(parseInt(digits, 10))
  }
}
