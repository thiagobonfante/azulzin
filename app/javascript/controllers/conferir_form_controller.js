import { Controller } from "@hotwired/stimulus"

// One Conferir button (.plans/credit-cards 03 §1, founder round 2026-07-22): the value
// input and the PDF input live in one form — a chosen file routes the submit to the
// reconciliation POST, otherwise the typed value goes to the stated-total PATCH.
// No-JS fallback: the form's default action is the PATCH, which rejects a blank value.
export default class extends Controller {
  static targets = ["value", "file"]
  static values = { reconUrl: String }

  route(event) {
    const hasFile = this.fileTarget.files.length > 0
    if (!hasFile && !this.valueTarget.value.trim()) {
      event.preventDefault()
      this.valueTarget.required = true
      this.element.reportValidity()
      return
    }
    if (hasFile) {
      this.element.action = this.reconUrlValue
      this.element.querySelector("input[name=_method]").value = "post"
    }
  }
}
