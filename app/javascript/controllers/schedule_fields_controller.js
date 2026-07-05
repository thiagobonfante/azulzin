import { Controller } from "@hotwired/stimulus"

// Adapts the income schedule "day" select to the chosen kind: "fixed_day" shows days of the
// month (1..31, "Dia 5"); "nth_business_day" relabels to ordinals and caps at 10. No-JS falls
// back to the fixed-day labels, and the server validates the day for the submitted kind.
export default class extends Controller {
  static targets = ["kind", "day"]

  connect() { this.toggle() }

  toggle() {
    const nth = this.kindTarget.value === "nth_business_day"
    for (const opt of this.dayTarget.options) {
      opt.textContent = nth ? opt.dataset.nth : opt.dataset.fixed
      const over = nth && parseInt(opt.value, 10) > 10
      opt.disabled = over
      opt.hidden = over
    }
    if (nth && parseInt(this.dayTarget.value, 10) > 10) this.dayTarget.value = "1"
  }
}
