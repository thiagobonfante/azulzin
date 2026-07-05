import { Controller } from "@hotwired/stimulus"

// Toggles the commitment form's kind-specific fieldsets (installment counts, fixed end date)
// and the card-instrument day hint. No-JS falls back to all fieldsets visible; the server
// only reads the fields relevant to the submitted kind.
export default class extends Controller {
  static targets = ["kind", "installment", "fixed", "instrument", "cardHint"]

  connect() { this.toggle() }
  disconnect() {} // no manual listeners; Stimulus tears down its own

  toggle() {
    const kind = this.selectedKind()
    if (this.hasInstallmentTarget) this.installmentTarget.hidden = kind !== "installment"
    if (this.hasFixedTarget) this.fixedTarget.hidden = kind !== "fixed"
    const card = this.hasInstrumentTarget && this.instrumentTarget.value.startsWith("credit_card")
    if (this.hasCardHintTarget) this.cardHintTarget.classList.toggle("hidden", !card)
  }

  selectedKind() {
    const checked = this.kindTargets.find((r) => r.checked)
    return checked ? checked.value : "installment"
  }
}
