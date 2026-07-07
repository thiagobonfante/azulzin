import { Controller } from "@hotwired/stimulus"

// Receipt lightbox (up-tier F5): opens the <dialog> and lazy-loads the full image on the
// first open — the closed dialog must not fetch the blob together with the row.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    const img = this.dialogTarget.querySelector("img[data-src]")
    if (img && !img.getAttribute("src")) img.src = img.dataset.src
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
