import { Controller } from "@hotwired/stimulus"

// The "sugerir" chip on the category budget field (up-tier 03 §3). One click asks
// /categories/:id/suggest_budget (deterministic 3-month median, LLM-free) and fills the
// field with a "sugestão" hint; 204 (no trailing-month history yet) shows the "ainda sem
// histórico" badge instead — a silent click reads as broken. The person can accept or
// overwrite freely — typing hides the hints. Progressive enhancement: with JS off the
// field is a plain money input.
export default class extends Controller {
  static targets = ["input", "hint", "empty"]
  static values = { url: String }

  async fill() {
    let data
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (res.status === 204) {
        this.toggleHints(false, true)
        return
      }
      if (res.status !== 200) return
      data = await res.json()
    } catch {
      return // offline — never disturb the form
    }
    this.inputTarget.value = data.budget_reais
    this.toggleHints(true, false)
  }

  hideHint() {
    this.toggleHints(false, false)
  }

  toggleHints(hint, empty) {
    if (this.hasHintTarget) this.hintTarget.hidden = !hint
    if (this.hasEmptyTarget) this.emptyTarget.hidden = !empty
  }
}
