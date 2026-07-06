import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// On-brand replacement for the native browser confirm(). Registered once, globally, via
// Turbo.config.forms.confirm — so it intercepts every button_to form and link_to ...
// data-turbo-method link that carries data-turbo-confirm, with no per-view changes.
// The controller is attached to the <dialog> itself, so this.element is the modal.
export default class extends Controller {
  static targets = ["message"]

  connect() {
    Turbo.config.forms.confirm = (message) => this.ask(message)
  }

  // Returns the Promise Turbo awaits: resolves true to proceed, false to abort.
  ask(message) {
    this.messageTarget.textContent = message
    this.previousFocus = document.activeElement
    this.element.returnValue = ""
    return new Promise((resolve) => {
      this.resolver = resolve
      this.element.showModal()
    })
  }

  confirm() {
    this.element.close("confirm")
  }

  // Fires for every close path — Confirm, Cancel, backdrop click, and Escape.
  onClose() {
    this.resolver?.(this.element.returnValue === "confirm")
    this.resolver = null
    this.previousFocus?.focus()
  }
}
