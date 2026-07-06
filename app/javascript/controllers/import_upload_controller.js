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
    let error = null
    for (const file of this.inputTarget.files) {
      const ext = "." + file.name.split(".").pop().toLowerCase()
      if (this.maxBytesValue && file.size > this.maxBytesValue) { error = this.tooLargeMessageValue; break }
      if (!allowed.includes(ext)) { error = this.badTypeMessageValue; break }
    }
    this.showError(error)
  }

  showError(message) {
    if (message) {
      this.warningTarget.textContent = message
      this.warningTarget.classList.remove("hidden")
      if (this.hasSubmitTarget) this.submitTarget.disabled = true
    } else {
      this.warningTarget.classList.add("hidden")
      if (this.hasSubmitTarget) this.submitTarget.disabled = false
    }
  }

  disconnect() {
    this.showError(null)
  }
}
