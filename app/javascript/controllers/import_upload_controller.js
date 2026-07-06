import { Controller } from "@hotwired/stimulus"

// Client-side pre-check of the file picker on the upload hero: block oversize / wrong-type
// files before the multipart POST and show an inline warning. Purely a faster error — the
// server re-validates type/size anyway (D8). All copy comes from data-*-value attributes so
// no user-facing string lives in JS (pt-BR i18n boundary).
export default class extends Controller {
  static targets = ["input", "warning", "submit"]
  static values = {
    tooLargeMessage: String,
    badTypeMessage: String,
    maxBytes: Number,
    accept: String
  }

  validate() {
    const allowed = this.acceptValue.split(",").map((s) => s.trim().toLowerCase())
    this.error = null
    for (const file of this.inputTarget.files) {
      const ext = "." + file.name.split(".").pop().toLowerCase()
      if (this.maxBytesValue && file.size > this.maxBytesValue) { this.error = this.tooLargeMessageValue; break }
      if (!allowed.includes(ext)) { this.error = this.badTypeMessageValue; break }
    }
    this.render()
  }

  // Fired by import_status_controller (window event) while any import is still processing.
  busyChanged(event) {
    this.busy = event.detail.busy
    this.render()
  }

  render() {
    if (this.error) {
      this.warningTarget.textContent = this.error
      this.warningTarget.classList.remove("hidden")
    } else {
      this.warningTarget.classList.add("hidden")
    }
    this.inputTarget.disabled = Boolean(this.busy)
    if (this.hasSubmitTarget) this.submitTarget.disabled = Boolean(this.busy || this.error)
  }

  disconnect() {
    this.busy = false
    this.error = null
    this.render()
  }
}
