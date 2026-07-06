import { Controller } from "@hotwired/stimulus"

// Multi-select parcel payment (commitment show page). Checked rows reveal the batch bar,
// count the selection and prefill the amount with the parcels' sum — the user adjusts it to
// what they actually paid (early batches usually carry a discount).
export default class extends Controller {
  static targets = ["checkbox", "bar", "count", "amount"]
  static values = { one: String, many: String }

  refresh() {
    const checked = this.checkboxTargets.filter((c) => c.checked)
    this.barTarget.hidden = checked.length === 0
    if (checked.length === 0) return
    const cents = checked.reduce((sum, c) => sum + parseInt(c.dataset.cents, 10), 0)
    this.countTarget.textContent = `${checked.length} ${checked.length === 1 ? this.oneValue : this.manyValue}`
    this.amountTarget.value = (cents / 100).toFixed(2).replace(".", ",")
  }
}
