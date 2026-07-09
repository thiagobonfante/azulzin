import { Controller } from "@hotwired/stimulus"

// One Diagnóstico orçamento slider row (.plans/goals draft screen): dragging live-previews the
// cap label; releasing submits the caps form so the server recomputes the three plans from the
// frozen baseline (the response Turbo-swaps only #goal_plan_area, so the sliders keep state).
// Values travel as integer cents end-to-end — no client-side money math beyond display.
export default class extends Controller {
  static targets = ["slider", "label"]

  preview() {
    this.labelTarget.textContent = this.format(parseInt(this.sliderTarget.value, 10))
  }

  commit() {
    this.element.closest("form").requestSubmit()
  }

  format(cents) {
    const locale = document.documentElement.lang || "pt-BR"
    return new Intl.NumberFormat(locale, { style: "currency", currency: "BRL" }).format(cents / 100)
  }
}
