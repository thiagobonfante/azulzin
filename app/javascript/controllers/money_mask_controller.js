import { Controller } from "@hotwired/stimulus"

// Whole-real money input mask (round 3 P1 — goals asks whole reais, no cents): digits only,
// re-rendered with locale thousands grouping (no currency symbol — the R$ prefix span is in
// the markup). Attached directly to the <input>. The server must prefill the input with a
// WHOLE-REAL string (never the default *_reais "60000,00" — a digits-only mask would read
// that ×100); Money.to_cents already parses "60.000"/"60,000" as whole reais.
export default class extends Controller {
  connect() { this.format() }

  format() {
    const digits = this.element.value.replace(/\D/g, "")
    if (digits === "") {
      this.element.value = ""
      return
    }
    const locale = document.documentElement.lang || "pt-BR"
    this.element.value = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(parseInt(digits, 10))
  }
}
