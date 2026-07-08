import { Controller } from "@hotwired/stimulus"

// Bottom-sheet (mobile) / centered (sm+) dialog that hosts the add + edit transaction forms in
// a shared "entry_form" turbo frame — the same drawer pattern as the commitment editor. The
// triggers (Adicionar, the FAB, a ledger row, the "guardar" badge) live OUTSIDE the dialog, so
// this controller sits on a common ancestor (the page wrapper) and they call #open. A successful
// Turbo submit (create / update / delete → 2xx) closes it; a 422 re-renders the form inside with
// errors and the sheet stays open. On close the frame is reset so the next open always refetches.
export default class extends Controller {
  static targets = ["dialog", "frame"]

  open() {
    if (this.hasDialogTarget) this.dialogTarget.showModal()
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // turbo:submit-end bubbles up from any form inside the sheet; close only on success (2xx).
  submitEnd(event) {
    if (event.detail?.success) this.close()
  }

  // After close, drop the loaded form so a reopen refetches (and never flashes the previous one).
  onClose() {
    if (!this.hasFrameTarget) return
    this.frameTarget.removeAttribute("src")
    this.frameTarget.removeAttribute("complete")
    this.frameTarget.innerHTML =
      '<div class="flex justify-center py-10"><span class="loading loading-spinner loading-md text-primary"></span></div>'
  }
}
