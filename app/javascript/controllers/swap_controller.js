import { Controller } from "@hotwired/stimulus"

// Two-panel swap: one visible, one hidden — toggle() flips both. Used by the Pagar
// modal's "Parcelei" button to trade the pay form for the financing form in place.
export default class extends Controller {
  static targets = ["a", "b"]

  toggle() {
    this.aTarget.classList.toggle("hidden")
    this.bTarget.classList.toggle("hidden")
    const shown = this.aTarget.classList.contains("hidden") ? this.bTarget : this.aTarget
    shown.querySelector("input:not([type=hidden]), select")?.focus()
  }

  // Back to the initial state (a visible) — wired to the dialog's close event so a
  // reopened modal never starts on the swapped panel.
  reset() {
    this.aTarget.classList.remove("hidden")
    this.bTarget.classList.add("hidden")
  }
}
