import { Controller } from "@hotwired/stimulus"

// Mobile-only (below lg) bottom-tab switch between the "Resumo" overview and the
// "Movimentos" ledger. Tapping a bottom-bar button flips the `hidden` class on the
// two content panels (and the quick-add FAB, which belongs to the Movimentos tab)
// and marks the active tab. Panels carry lg:block / the FAB carries lg:hidden, so
// at lg+ the toggle is inert and everything renders as before.
export default class extends Controller {
  static targets = ["panel", "tab"]

  show(event) {
    const name = event.currentTarget.dataset.panel

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.panel !== name)
    })

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.panel === name
      tab.classList.toggle("text-primary", active)
      tab.classList.toggle("text-base-content/60", !active)
      tab.setAttribute("aria-current", active ? "page" : "false")
    })
  }
}
