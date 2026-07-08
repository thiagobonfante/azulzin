import { Controller } from "@hotwired/stimulus"

// Screen 1 (.plans/goals 02 §2): show the "when" (target date) field only for a purchase goal;
// a savings-rate goal hides it and relabels the value. Radios drive it. No-JS shows both groups
// and the server validates (target_date required for purchase, forbidden for savings_rate).
export default class extends Controller {
  static targets = ["kind", "dateGroup", "valueLabel"]
  static values = { purchaseLabel: String, savingsLabel: String }

  connect() { this.toggle() }

  toggle() {
    const purchase = this.kindTargets.find((r) => r.checked)?.value === "purchase"
    if (this.hasDateGroupTarget) this.dateGroupTarget.hidden = !purchase
    if (this.hasValueLabelTarget) {
      this.valueLabelTarget.textContent = purchase ? this.purchaseLabelValue : this.savingsLabelValue
    }
  }
}
