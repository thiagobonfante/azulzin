import { Controller } from "@hotwired/stimulus"

// Three-state theme picker: "" (auto, follows the OS), "azulzin", "azulzin-dark".
// The choice lives in localStorage only; the early script in layouts/_meta applies
// it before first paint. Auto = no data-theme attribute, daisyUI's prefersdark rules.
// ponytail: client-side only — persist on user.settings if it ever must roam devices
export default class extends Controller {
  connect() {
    const current = localStorage.getItem("theme") || ""
    this.element.querySelectorAll("input[type=radio]").forEach(input => {
      input.checked = input.value === current
    })
  }

  set(event) {
    const theme = event.target.value
    if (theme) {
      localStorage.setItem("theme", theme)
      document.documentElement.dataset.theme = theme
    } else {
      localStorage.removeItem("theme")
      delete document.documentElement.dataset.theme
    }
  }
}
