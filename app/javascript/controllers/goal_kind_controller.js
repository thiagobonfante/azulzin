import { Controller } from "@hotwired/stimulus"

// Screen 1 (.plans/goals 02 §2): purchase shows the "when" + "already saved" fields; savings-rate
// hides them, relabels the value, and shows the current-guardado hint instead. Radios drive it.
// Hidden sections also get their inputs DISABLED (hidden alone still submits — the pre-filled
// date select would trip the savings_rate absence validation). No-JS shows every group and the
// server normalizes kind-inapplicable fields (GoalsController#create_params) before validating.
export default class extends Controller {
  static targets = ["kind", "purchaseOnly", "savingsOnly", "valueLabel"]
  static values = { purchaseLabel: String, savingsLabel: String }

  connect() { this.toggle() }

  toggle() {
    const purchase = this.kindTargets.find((r) => r.checked)?.value === "purchase"
    this.purchaseOnlyTargets.forEach((el) => {
      el.hidden = !purchase
      el.querySelectorAll("input, select").forEach((i) => (i.disabled = !purchase))
    })
    this.savingsOnlyTargets.forEach((el) => (el.hidden = purchase))
    if (this.hasValueLabelTarget) {
      this.valueLabelTarget.textContent = purchase ? this.purchaseLabelValue : this.savingsLabelValue
    }
  }
}
