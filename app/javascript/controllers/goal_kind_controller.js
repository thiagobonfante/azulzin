import { Controller } from "@hotwired/stimulus"

// Screen 1 (.plans/goals 02 §2): purchase shows the "when" + "already saved" fields; savings-rate
// hides them, relabels the value, and shows the current-guardado hint instead. Radios drive it.
// No-JS shows every group and the server validates (target_date required for purchase, forbidden
// for savings_rate).
export default class extends Controller {
  static targets = ["kind", "purchaseOnly", "savingsOnly", "valueLabel"]
  static values = { purchaseLabel: String, savingsLabel: String }

  connect() { this.toggle() }

  toggle() {
    const purchase = this.kindTargets.find((r) => r.checked)?.value === "purchase"
    this.purchaseOnlyTargets.forEach((el) => (el.hidden = !purchase))
    this.savingsOnlyTargets.forEach((el) => (el.hidden = purchase))
    if (this.hasValueLabelTarget) {
      this.valueLabelTarget.textContent = purchase ? this.purchaseLabelValue : this.savingsLabelValue
    }
  }
}
