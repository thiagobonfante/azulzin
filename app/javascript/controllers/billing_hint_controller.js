import { Controller } from "@hotwired/stimulus"

// Live "melhor dia de compra" hint on the credit-card billing fields. When the closing
// offset ≥ due day, the closing date falls in the PRIOR month (a legal config), so the
// naive due − offset + 1 goes non-positive — the mod-wrap keeps the illustrative day in
// 1..31. The exact clamped short-month math lives server-side in Billing; this is a hint.
export default class extends Controller {
  static targets = ["dueDay", "offset", "hint"]
  static values = { template: String }

  update() {
    const due = parseInt(this.dueDayTarget.value, 10)
    if (!due) {
      this.hintTarget.classList.add("hidden")
      return
    }
    const offset = parseInt(this.offsetTarget.value, 10) || 0
    const day = ((((due - offset) % 31) + 31) % 31) + 1
    this.hintTarget.textContent = this.templateValue.replace("{day}", day)
    this.hintTarget.classList.remove("hidden")
  }
}
