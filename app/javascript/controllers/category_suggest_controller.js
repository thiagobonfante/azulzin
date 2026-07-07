import { Controller } from "@hotwired/stimulus"

// Merchant-memory preselect for the quick-add category picker (auto-categories 03 §1).
// On merchant change it asks /categories/suggest (LLM-free) and, ONLY while the picker is
// still untouched and empty, preselects the suggested category with a "sugestão" hint.
// Any manual interaction with the picker wins permanently. Progressive enhancement: with
// JS off the form behaves exactly as before.
export default class extends Controller {
  static targets = ["hint"]
  static values = { url: String }

  connect() {
    this.touched = false
    // A click on any picker option = the person chose; stop suggesting for this form.
    this._onPick = (event) => {
      if (event.target.closest('[data-category-picker-target="option"]')) {
        this.touched = true
        this.hideHint()
      }
    }
    this.element.addEventListener("click", this._onPick, true)
  }

  disconnect() {
    this.element.removeEventListener("click", this._onPick, true)
    this.abort?.abort()
  }

  async fetch(event) {
    const merchant = event.target.value.trim()
    const input = this.element.querySelector('[data-category-picker-target="input"]')
    if (!merchant || this.touched || !input || input.value !== "") return

    this.abort?.abort()
    this.abort = new AbortController()
    let data
    try {
      const res = await fetch(`${this.urlValue}?merchant=${encodeURIComponent(merchant)}`, {
        headers: { Accept: "application/json" }, signal: this.abort.signal
      })
      if (res.status !== 200) return
      data = await res.json()
    } catch {
      return // aborted or offline — never disturb the form
    }
    if (this.touched || input.value !== "") return // person acted while we fetched

    const option = this.element.querySelector(
      `[data-category-picker-target="option"][data-value="${data.category_id}"]`
    )
    if (!option) return
    const display = this.element.querySelector('[data-category-picker-target="display"]')
    input.value = data.category_id
    display.innerHTML = option.querySelector("[data-label]").innerHTML
    display.classList.remove("text-base-content/50")
    if (this.hasHintTarget) this.hintTarget.hidden = false
  }

  hideHint() {
    if (this.hasHintTarget) this.hintTarget.hidden = true
  }
}
