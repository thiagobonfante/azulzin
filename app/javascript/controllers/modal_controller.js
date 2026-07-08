import { Controller } from "@hotwired/stimulus"

// Generic <dialog> modal: a trigger (data-action="modal#open") + a dialog target inside the
// controller's scope. openValue re-opens it on connect — used to bring a form back up when a
// 422 re-render lands with validation errors.
export default class extends Controller {
  static targets = ["dialog"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
