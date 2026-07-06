import { Controller } from "@hotwired/stimulus"

// Closes a <details class="dropdown"> when clicking outside it or pressing Escape —
// the native element only toggles on its own summary, which leaves stale panels open.
export default class extends Controller {
  connect() {
    this._onDocClick = (event) => {
      if (this.element.open && !this.element.contains(event.target)) this.element.open = false
    }
    this._onKeydown = (event) => {
      if (event.key === "Escape") this.element.open = false
    }
    document.addEventListener("click", this._onDocClick)
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
    document.removeEventListener("keydown", this._onKeydown)
  }
}
