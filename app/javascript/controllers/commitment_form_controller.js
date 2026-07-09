import { Controller } from "@hotwired/stimulus"

// Toggles the commitment form's kind-specific fieldsets (installment counts, fixed end date,
// savings destination) and the card-instrument day hint. No-JS falls back to all fieldsets
// visible; the server only reads the fields relevant to the submitted kind. For savings the
// card options are hidden as a client aid — the model validation is the backstop.
export default class extends Controller {
  static targets = ["kind", "installment", "fixed", "savings", "category", "instrument", "cardHint"]

  connect() { this.toggle() }
  disconnect() {} // no manual listeners; Stimulus tears down its own

  toggle() {
    const kind = this.selectedKind()
    if (this.hasInstallmentTarget) this.installmentTarget.hidden = kind !== "installment"
    if (this.hasFixedTarget) this.fixedTarget.hidden = kind !== "fixed"
    if (this.hasSavingsTarget) this.savingsTarget.hidden = kind !== "savings"
    if (this.hasCategoryTarget) this.categoryTarget.hidden = kind === "savings"
    if (this.hasInstrumentTarget) this.restrictInstrument(kind === "savings")
    const card = this.hasInstrumentTarget && this.instrumentTarget.value.startsWith("credit_card")
    if (this.hasCardHintTarget) this.cardHintTarget.classList.toggle("hidden", !card)
  }

  // Savings moves money FROM a bank account: hide/disable the cards optgroup and, if a card
  // was selected, fall back to the first bank account option.
  restrictInstrument(savings) {
    this.instrumentTarget.querySelectorAll("optgroup").forEach((group) => {
      if (!group.querySelector("option")?.value.startsWith("credit_card")) return
      group.hidden = savings
      group.disabled = savings
    })
    if (savings && this.instrumentTarget.value.startsWith("credit_card")) {
      const bank = Array.from(this.instrumentTarget.options).find((o) => o.value.startsWith("bank_account"))
      if (bank) this.instrumentTarget.value = bank.value
    }
  }

  selectedKind() {
    const checked = this.kindTargets.find((r) => r.checked)
    return checked ? checked.value : "installment"
  }
}
