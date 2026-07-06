import { Controller } from "@hotwired/stimulus"

// The mobile "+" FAB opens the ledger's inline add-entry form — a Turbo frame that lives at
// the bottom of the transactions page — and scrolls it into view. Without this the form loads
// below the fold and tapping the button looks like it did nothing.
export default class extends Controller {
  open() {
    const frame = document.getElementById("new_entry")
    if (!frame) return
    const reveal = () => {
      frame.removeEventListener("turbo:frame-load", reveal)
      frame.scrollIntoView({ behavior: "smooth", block: "center" })
      frame.querySelector("input, select")?.focus({ preventScroll: true })
    }
    frame.addEventListener("turbo:frame-load", reveal)
  }
}
