import { Controller } from "@hotwired/stimulus"

// "Começar do zero" vs "já tenho um valor guardado" (round 3 P3). Picking zero hides the
// reveal block AND clears its values (a toggled-back-to-zero submit must send blank, never a
// stale amount/caixinha) — clearing instead of disabling keeps this independent from
// goal_kind's disable-hidden-inputs pass over the same purchaseOnly wrapper.
export default class extends Controller {
  static targets = ["mode", "fields"]

  connect() { this.toggle() }

  toggle() {
    const some = this.modeTargets.find((r) => r.checked)?.value === "some"
    this.fieldsTarget.hidden = !some
    if (some) return
    this.fieldsTarget.querySelectorAll("input").forEach((input) => (input.value = ""))
    this.fieldsTarget.querySelectorAll('[data-controller~="institution-select"]').forEach((el) => {
      this.application.getControllerForElementAndIdentifier(el, "institution-select")?.clearSelection()
    })
  }
}
