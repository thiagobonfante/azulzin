import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Mobile month navigation by horizontal swipe, mirroring the month_nav arrows.
// Swipe left → next month, swipe right → previous month (carousel convention),
// navigating to the same URLs the arrows use. Guards: only a dominant-horizontal
// gesture past a threshold fires; vertical scrolls and swipes that begin inside a
// horizontally-scrollable element (filter chips, category bars) are ignored so we
// never hijack their own scroll.
export default class extends Controller {
  static values = { prevUrl: String, nextUrl: String }

  connect() {
    this.startX = null
    this.startY = null
    this.onStart = this.onStart.bind(this)
    this.onEnd = this.onEnd.bind(this)
    this.element.addEventListener("touchstart", this.onStart, { passive: true })
    this.element.addEventListener("touchend", this.onEnd, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("touchstart", this.onStart)
    this.element.removeEventListener("touchend", this.onEnd)
  }

  onStart(event) {
    if (event.touches.length !== 1 || this.inScrollable(event.target)) {
      this.startX = null
      return
    }
    this.startX = event.touches[0].clientX
    this.startY = event.touches[0].clientY
  }

  onEnd(event) {
    if (this.startX === null) return
    const touch = event.changedTouches[0]
    const dx = touch.clientX - this.startX
    const dy = touch.clientY - this.startY
    this.startX = null

    const THRESHOLD = 60
    if (Math.abs(dx) < THRESHOLD) return
    if (Math.abs(dx) <= Math.abs(dy)) return // not dominant-horizontal — likely a scroll

    const url = dx < 0 ? this.nextUrlValue : this.prevUrlValue
    if (url) Turbo.visit(url)
  }

  // True if the touch began inside an element that can scroll horizontally, so its
  // own swipe (chip rows, bars) wins over month navigation.
  inScrollable(node) {
    let el = node
    while (el && el !== this.element) {
      if (el.nodeType === 1) {
        const overflowX = getComputedStyle(el).overflowX
        if ((overflowX === "auto" || overflowX === "scroll") && el.scrollWidth > el.clientWidth) {
          return true
        }
      }
      el = el.parentElement
    }
    return false
  }
}
