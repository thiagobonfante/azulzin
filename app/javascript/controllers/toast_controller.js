import { Controller } from "@hotwired/stimulus"

// Self-dismissing toast: fades out and removes itself after a few seconds, or immediately on
// click (wired via data-action by shared/_toast). Cleans its timer up if navigated away first.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 5000)
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.classList.add("opacity-0")
    setTimeout(() => this.element.remove(), 300)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
