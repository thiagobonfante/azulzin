import { Controller } from "@hotwired/stimulus"

// Live running diff for the left-behind picker (.plans/credit-cards 03 §1): "our total
// minus the checked rows" chases the bank's number; the match line lights up the moment
// they agree. Server does the writes — this only narrates the sum.
export default class extends Controller {
  static targets = ["checkbox", "remaining", "match"]
  static values = { computed: Number, stated: Number }

  connect() { this.recount() }

  recount() {
    const selected = this.checkboxTargets
      .filter((box) => box.checked)
      .reduce((sum, box) => sum + parseInt(box.dataset.amount, 10), 0)
    const remaining = this.computedValue - selected
    this.remainingTarget.textContent = this.format(remaining)
    const matches = remaining === this.statedValue
    this.matchTarget.classList.toggle("hidden", !matches)
    this.remainingTarget.classList.toggle("text-success", matches)
  }

  format(cents) {
    const locale = document.documentElement.lang || "pt-BR"
    return new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(cents / 100)
  }
}
