import { Controller } from "@hotwired/stimulus"

// Live partial-payment warning in the Pagar modal (.plans/credit-cards 02 §4): debounced
// fetch of the SERVER-rendered panel — all money math stays in Ruby.
export default class extends Controller {
  static targets = ["amount", "panel"]
  static values = { url: String }

  disconnect() { clearTimeout(this.timer) }

  recount() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.refresh(), 300)
  }

  async refresh() {
    const amount = encodeURIComponent(this.amountTarget.value)
    const response = await fetch(`${this.urlValue}?amount_reais=${amount}`, { headers: { Accept: "text/html" } })
    if (response.ok) this.panelTarget.innerHTML = await response.text()
  }
}
