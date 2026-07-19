import { Controller } from "@hotwired/stimulus"

// Mobile-only (below lg) bottom-tab switch between the "Resumo" overview and the
// "Movimentos" ledger. Tapping a bottom-bar button flips the `hidden` class on the
// two content panels (and the quick-add FAB, which belongs to the Movimentos tab)
// and marks the active tab. Panels carry lg:block / the FAB carries lg:hidden, so
// at lg+ the toggle is inert and everything renders as before.
export default class extends Controller {
  static targets = ["panel", "tab"]

  // Month navigation (swipe or arrows) is a full Turbo visit, which used to reset the
  // screen to Resumo. The active tab lives in sessionStorage so the choice survives
  // navigation within the browser session; a fresh session starts on Resumo as before.
  connect() {
    const saved = sessionStorage.getItem("transactions:tab")
    if (saved && saved !== "summary") this.select(saved)
  }

  show(event) {
    this.select(event.currentTarget.dataset.panel)
  }

  select(name) {
    sessionStorage.setItem("transactions:tab", name)

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
