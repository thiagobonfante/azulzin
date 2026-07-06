import { Controller } from "@hotwired/stimulus"

// One-tap copy for a short code (the WhatsApp activation code). Copies the source element's
// text, then briefly swaps the copy glyph for a check so the tap is acknowledged.
export default class extends Controller {
  static targets = ["source", "copyIcon", "doneIcon"]

  copy() {
    if (!navigator.clipboard) return
    navigator.clipboard
      .writeText(this.sourceTarget.textContent.trim())
      .then(() => this.flash())
      .catch(() => {})
  }

  flash() {
    this.toggle(true)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.toggle(false), 1500)
  }

  toggle(done) {
    if (this.hasCopyIconTarget) this.copyIconTarget.hidden = done
    if (this.hasDoneIconTarget) this.doneIconTarget.hidden = !done
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
