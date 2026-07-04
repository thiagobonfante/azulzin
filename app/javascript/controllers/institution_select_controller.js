import { Controller } from "@hotwired/stimulus"

// A searchable institution picker with brand avatars. The real value lives in a hidden
// input (target "input"); a <noscript> native <select> is the no-JS fallback.
export default class extends Controller {
  static targets = ["input", "display", "panel", "search", "option"]

  connect() {
    this._onDocumentClick = this.onDocumentClick.bind(this)
    this._placeholderHTML = this.displayTarget.innerHTML
    this._form = this.element.closest("form")
    this._onFormReset = () => this.clearSelection()
    this._form?.addEventListener("reset", this._onFormReset)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocumentClick)
    this._form?.removeEventListener("reset", this._onFormReset)
  }

  // Restore the placeholder when the surrounding form is reset (after a successful add).
  clearSelection() {
    this.inputTarget.value = ""
    this.displayTarget.innerHTML = this._placeholderHTML
    this.displayTarget.classList.add("text-base-content/50")
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.hidden ? this.open() : this.hide()
  }

  open() {
    this.panelTarget.hidden = false
    this.searchTarget.value = ""
    this.filter()
    this.searchTarget.focus()
    document.addEventListener("click", this._onDocumentClick)
  }

  hide() {
    this.panelTarget.hidden = true
    document.removeEventListener("click", this._onDocumentClick)
  }

  onDocumentClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  pick(event) {
    const option = event.currentTarget
    this.inputTarget.value = option.dataset.value
    this.displayTarget.innerHTML = option.querySelector("[data-label]").innerHTML
    this.displayTarget.classList.remove("text-base-content/50")
    this.hide()
  }

  filter() {
    const q = this.searchTarget.value.trim().toLowerCase()
    this.optionTargets.forEach((opt) => {
      opt.hidden = q !== "" && !opt.dataset.name.includes(q)
    })
  }

  onKeydown(event) {
    if (event.key === "Escape") this.hide()
  }
}
