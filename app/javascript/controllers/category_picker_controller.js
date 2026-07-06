import { Controller } from "@hotwired/stimulus"

// Category picker with color + icon swatches. A styled dropdown over a hidden field —
// same shape as entry-instrument, minus the payment-method coupling. The <noscript>
// native <select> is the no-JS path.
export default class extends Controller {
  static targets = ["input", "display", "button", "panel", "option"]

  connect() {
    this._placeholder = this.displayTarget.innerHTML
    this._onDocClick = this.onDocClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.hidden ? this.open() : this.hide()
  }

  open() {
    this.panelTarget.hidden = false
    document.addEventListener("click", this._onDocClick)
  }

  hide() {
    this.panelTarget.hidden = true
    document.removeEventListener("click", this._onDocClick)
  }

  onDocClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  pick(event) {
    const option = event.currentTarget
    this.inputTarget.value = option.dataset.value
    this.displayTarget.innerHTML = option.querySelector("[data-label]").innerHTML
    this.displayTarget.classList.toggle("text-base-content/50", option.dataset.value === "")
    this.hide()
  }
}
