import { Controller } from "@hotwired/stimulus"

// Self-dismissing toast: removes itself after a few seconds (or when clicked/navigated away).
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.element.remove(), 6000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
