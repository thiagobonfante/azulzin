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
    // Whole reais only (round 3 P1) — slider positions are already whole-real cents
    // (server ceils min/max/value); Math.ceil is defensive.
    return new Intl.NumberFormat(locale, {
      style: "currency", currency: "BRL", minimumFractionDigits: 0, maximumFractionDigits: 0
    }).format(Math.ceil(cents / 100))
  }
}
