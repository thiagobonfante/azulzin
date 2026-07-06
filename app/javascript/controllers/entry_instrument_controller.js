import { Controller } from "@hotwired/stimulus"

// Add-form payment picker. A payment-method segmented control (expense only) drives a
// brand-avatar instrument picker: "crédito" narrows the options to cards, "débito / pix /
// boleto" to bank accounts, and the sole option of the chosen type is auto-selected. With no
// method buttons (income) every option is selectable. The real value is a hidden `instrument`
// token (bank_account-ID / credit_card-ID); a <noscript> native <select> is the no-JS path.
export default class extends Controller {
  static targets = ["method", "methodInput", "input", "display", "button", "panel", "search", "option"]

  connect() {
    this._placeholder = this.hasDisplayTarget ? this.displayTarget.innerHTML : ""
    this._onDocClick = this.onDocClick.bind(this)
    this._form = this.element.closest("form")
    this._onReset = () => this.reset()
    this._form?.addEventListener("reset", this._onReset)

    this._type = this.defaultType()

    if (this.inputTarget.value) this.reflectSelection()
    this.render()
    this.autoselect()
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
    this._form?.removeEventListener("reset", this._onReset)
  }

  // The active method button's type. No buttons (income) — or none active (review card with
  // an unmapped extracted method, e.g. dinheiro) — ⇒ null type ⇒ every option is selectable.
  defaultType() {
    const active = this.methodTargets.find((b) => b.dataset.active === "true")
    return active ? active.dataset.type : null
  }

  selectMethod(event) {
    const btn = event.currentTarget
    if (this.hasMethodInputTarget) this.methodInputTarget.value = btn.dataset.method
    this.methodTargets.forEach((b) => {
      const on = b === btn
      b.dataset.active = on ? "true" : "false"
      b.classList.toggle("btn-primary", on)
      b.classList.toggle("btn-ghost", !on)
    })

    this._type = btn.dataset.type
    // Drop a selection that no longer fits the chosen type, then re-run auto-select.
    const current = this.optionForValue(this.inputTarget.value)
    if (current && current.dataset.type !== this._type) this.clearSelection()
    this.render()
    this.autoselect()
  }

  // Auto-pick when exactly one option matches the active type — but never override an explicit
  // choice the user already made.
  autoselect() {
    if (this.inputTarget.value) return
    const matches = this.optionTargets.filter((o) => !this._type || o.dataset.type === this._type)
    if (matches.length === 1) this.choose(matches[0])
  }

  render() {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    this.optionTargets.forEach((opt) => {
      const typeOk = !this._type || opt.dataset.type === this._type
      const nameOk = q === "" || opt.dataset.name.includes(q)
      opt.hidden = !(typeOk && nameOk)
    })
  }

  applySearch() {
    this.render()
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.hidden ? this.open() : this.hide()
  }

  open() {
    this.panelTarget.hidden = false
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
      this.render()
      this.searchTarget.focus()
    }
    document.addEventListener("click", this._onDocClick)
  }

  hide() {
    this.panelTarget.hidden = true
    document.removeEventListener("click", this._onDocClick)
  }

  onDocClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  onKeydown(event) {
    if (event.key === "Escape") this.hide()
  }

  pick(event) {
    this.choose(event.currentTarget)
    this.hide()
  }

  choose(option) {
    this.inputTarget.value = option.dataset.value
    this.displayTarget.innerHTML = option.querySelector("[data-label]").innerHTML
    this.displayTarget.classList.remove("text-base-content/50")
  }

  // Reflect a pre-filled hidden value (validation-error re-render) in the button label.
  reflectSelection() {
    const option = this.optionForValue(this.inputTarget.value)
    if (option) this.choose(option)
  }

  clearSelection() {
    this.inputTarget.value = ""
    this.displayTarget.innerHTML = this._placeholder
    this.displayTarget.classList.add("text-base-content/50")
  }

  reset() {
    this.clearSelection()
    this._type = this.defaultType()
    this.render()
    this.autoselect()
  }

  optionForValue(value) {
    return value ? this.optionTargets.find((o) => o.dataset.value === value) : null
  }
}
