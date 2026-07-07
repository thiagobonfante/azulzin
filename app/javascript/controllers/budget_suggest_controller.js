import { Controller } from "@hotwired/stimulus"

// The "sugerir" chip on the category budget field (up-tier 03 §3). One click asks
// /categories/:id/suggest_budget (deterministic 3-month median, LLM-free) and fills the
// field with a "sugestão" hint; 204 (no history yet) fills nothing. The person can accept
// or overwrite freely — typing hides the hint. Progressive enhancement: with JS off the
// field is a plain money input.
export default class extends Controller {
  static targets = ["input", "hint"]
  static values = { url: String }

  async fill() {
    let data
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (res.status !== 200) return
      data = await res.json()
    } catch {
      return // offline — never disturb the form
    }
    this.inputTarget.value = data.budget_reais
    if (this.hasHintTarget) this.hintTarget.hidden = false
  }

  hideHint() {
    if (this.hasHintTarget) this.hintTarget.hidden = true
  }
}
