import { Controller } from "@hotwired/stimulus"

// Mobile-only disclosure for the sidebar "add" card: the trigger button (lg:hidden) toggles
// the card's `hidden` class — on lg+ the card's `lg:block` always wins, so desktop stays open.
export default class extends Controller {
  static targets = ["content", "button"]

  toggle() {
    const hidden = this.contentTarget.classList.toggle("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", String(!hidden))
    if (!hidden) this.contentTarget.querySelector("input:not([type=hidden]), select, button")?.focus()
  }
}
